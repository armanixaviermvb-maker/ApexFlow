"""Walk-forward window planning and MT5 Strategy Tester configuration files.

Each window is optimised on its in-sample (IS) period and then evaluated,
unchanged, on the following out-of-sample (OOS) period. The generated .ini
files can be run with:

    terminal64.exe /config:"<path to .ini>"

Model=4 is "Every tick based on real ticks".
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from pathlib import Path


@dataclass(frozen=True)
class Window:
    index: int
    is_start: date
    is_end: date
    oos_start: date
    oos_end: date


def add_months(d: date, months: int) -> date:
    y, m = divmod(d.month - 1 + months, 12)
    return date(d.year + y, m + 1, 1)


def walk_forward_windows(start: date, end: date, is_months: int, oos_months: int, step_months: int | None = None) -> list[Window]:
    """Rolling windows; OOS periods never overlap their own IS period."""
    if is_months <= 0 or oos_months <= 0:
        raise ValueError("window lengths must be positive")
    step = step_months or oos_months
    start = date(start.year, start.month, 1)
    windows = []
    i = 0
    while True:
        is_start = add_months(start, i * step)
        oos_start = add_months(is_start, is_months)
        oos_end = add_months(oos_start, oos_months)
        if oos_end > end:
            break
        windows.append(Window(i, is_start, oos_start, oos_start, oos_end))
        i += 1
    return windows


def tester_ini(
    *,
    symbol: str,
    from_date: date,
    to_date: date,
    deposit: float,
    currency: str = "USD",
    leverage: int = 100,
    period: str = "M5",
    optimization: bool = False,
    report: str = "ApexFlow_report",
    inputs: dict[str, str] | None = None,
    expert: str = r"ApexFlow\ApexFlow.ex5",
) -> str:
    lines = [
        "[Tester]",
        f"Expert={expert}",
        f"Symbol={symbol}",
        f"Period={period}",
        "Model=4",
        f"FromDate={from_date:%Y.%m.%d}",
        f"ToDate={to_date:%Y.%m.%d}",
        "ForwardMode=0",
        f"Deposit={deposit:g}",
        f"Currency={currency}",
        f"Leverage={leverage}",
        f"Optimization={2 if optimization else 0}",
        "OptimizationCriterion=6",
        f"Report={report}",
        "ReplaceReport=1",
        "ShutdownTerminal=1",
        "Visual=0",
    ]
    if inputs:
        lines.append("[TesterInputs]")
        # Strategy Tester always runs in TEST mode: orders are simulated.
        merged = {"InpTradingMode": "0"} | dict(inputs)
        lines += [f"{k}={v}" for k, v in merged.items()]
    return "\r\n".join(lines) + "\r\n"


def write_walk_forward_plan(out_dir: str | Path, symbol: str, windows: list[Window], deposit: float, **kwargs) -> list[Path]:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    paths = []
    for w in windows:
        for phase, a, b, opt in (("IS", w.is_start, w.is_end, True), ("OOS", w.oos_start, w.oos_end, False)):
            name = f"wf{w.index:02d}_{phase}_{symbol}"
            p = out / f"{name}.ini"
            p.write_text(
                tester_ini(symbol=symbol, from_date=a, to_date=b, deposit=deposit, optimization=opt, report=name, **kwargs),
                encoding="utf-8",
            )
            paths.append(p)
    return paths


def write_ab_plan(out_dir: str | Path, symbol: str, windows: list[Window], deposit: float,
                  base_inputs: dict[str, str] | None = None, **kwargs) -> list[Path]:
    """A/B plan: for every out-of-sample window, two runs with IDENTICAL inputs except
    InpEnableAuctionRejection (false = BASE, true = BASE + AUCTION_REJECTION).
    Each run writes its own journals via InpJournalTag (e.g. base_wf00 / ar_wf00).
    Parameters are fixed (no optimisation) so the comparison isolates the strategy."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    paths = []
    for w in windows:
        for variant, enabled in (("base", "false"), ("ar", "true")):
            tag = f"{variant}_wf{w.index:02d}"
            inputs = dict(base_inputs or {})
            inputs["InpEnableAuctionRejection"] = enabled
            inputs["InpJournalTag"] = tag
            p = out / f"{tag}_{symbol}.ini"
            p.write_text(
                tester_ini(symbol=symbol, from_date=w.oos_start, to_date=w.oos_end, deposit=deposit,
                           optimization=False, report=f"{tag}_{symbol}", inputs=inputs, **kwargs),
                encoding="utf-8",
            )
            paths.append(p)
    return paths
