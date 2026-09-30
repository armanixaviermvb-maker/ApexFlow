"""Load the CSV journals written by the EA (Common\\Files\\ApexFlow\\).

trades_<symbol>_<magic>[_tester].csv   one row per closed trade
signals_<symbol>_<magic>[_tester].csv  one row per signal evaluation
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

TIME_FORMAT = "%Y.%m.%d %H:%M:%S"


def parse_time(value: str) -> datetime:
    return datetime.strptime(value.strip(), TIME_FORMAT)


def _float(value: str, default: float = 0.0) -> float:
    value = (value or "").strip()
    return float(value) if value else default


@dataclass(frozen=True)
class Trade:
    trade_id: str
    symbol: str
    direction: str
    strategy: str
    regime: str
    session: str
    open_time: datetime
    close_time: datetime
    duration_min: float
    entry: float
    exit: float
    initial_sl: float
    volume: float
    risk_money: float
    profit: float
    r_multiple: float
    exit_reason: str
    buy_score: float
    sell_score: float
    strategy_version: str

    @property
    def is_win(self) -> bool:
        return self.profit > 0

    @property
    def is_loss(self) -> bool:
        return self.profit < 0


@dataclass(frozen=True)
class Signal:
    time: datetime
    symbol: str
    session: str
    regime: str
    decision: str
    strategy: str
    buy_score: float
    sell_score: float
    atr_percentile: float
    spread_points: float
    status: str
    reject_reason: str
    strategy_version: str


def _rows(path: Path) -> Iterable[dict]:
    with open(path, newline="", encoding="latin-1") as fh:
        yield from csv.DictReader(fh)


def load_trades(path: str | Path) -> list[Trade]:
    trades = []
    for row in _rows(Path(path)):
        trades.append(
            Trade(
                trade_id=row["trade_id"],
                symbol=row["symbol"],
                direction=row["direction"],
                strategy=row["strategy"],
                regime=row["regime"],
                session=row["session"],
                open_time=parse_time(row["open_time"]),
                close_time=parse_time(row["close_time"]),
                duration_min=_float(row["duration_min"]),
                entry=_float(row["entry"]),
                exit=_float(row["exit"]),
                initial_sl=_float(row["initial_sl"]),
                volume=_float(row["volume"]),
                risk_money=_float(row["risk_money"]),
                profit=_float(row["profit"]),
                r_multiple=_float(row["r_multiple"]),
                exit_reason=row["exit_reason"],
                buy_score=_float(row["buy_score"]),
                sell_score=_float(row["sell_score"]),
                strategy_version=row.get("strategy_version", ""),
            )
        )
    trades.sort(key=lambda t: t.close_time)
    return trades


def load_signals(path: str | Path) -> list[Signal]:
    signals = []
    for row in _rows(Path(path)):
        signals.append(
            Signal(
                time=parse_time(row["time"]),
                symbol=row["symbol"],
                session=row["session"],
                regime=row["regime"],
                decision=row["decision"],
                strategy=row["strategy"],
                buy_score=_float(row["buy_score"]),
                sell_score=_float(row["sell_score"]),
                atr_percentile=_float(row["atr_percentile"], 50.0),
                spread_points=_float(row["spread_points"]),
                status=row["status"],
                reject_reason=row.get("reject_reason", ""),
                strategy_version=row.get("strategy_version", ""),
            )
        )
    signals.sort(key=lambda s: s.time)
    return signals
