"""
logging_utils.py
================
Structured logging for the MIMIC-IV sepsis pipeline.

Every script calls `setup_logging(__name__)` at the top of main() to get a
named logger with consistent formatting. Operations are timed with the
`step()` context manager, which logs duration automatically.

Usage
-----
    from logging_utils import setup_logging, step

    def main():
        log = setup_logging("02_extract_cohort")
        log.info("starting cohort extraction")

        with step(log, "loading icustays"):
            df = pd.read_csv(...)

        log.info("final cohort: %d stays", len(df))
"""
from __future__ import annotations

import logging
import sys
import time
from contextlib import contextmanager
from typing import Generator

_CONFIGURED = False

LOG_FORMAT = "[%(asctime)s] %(name)-28s %(levelname)-5s  %(message)s"
LOG_DATEFMT = "%H:%M:%S"


def setup_logging(
    name: str,
    *,
    level: int = logging.INFO,
    log_file: str | None = None,
) -> logging.Logger:
    """Return a named logger for a pipeline script.

    First call configures the root logger (stderr + optional file).
    Subsequent calls just return a child logger.
    """
    global _CONFIGURED
    if not _CONFIGURED:
        root = logging.getLogger()
        root.setLevel(logging.DEBUG)

        stderr_handler = logging.StreamHandler(sys.stderr)
        stderr_handler.setLevel(level)
        stderr_handler.setFormatter(logging.Formatter(LOG_FORMAT, datefmt=LOG_DATEFMT))
        root.addHandler(stderr_handler)

        if log_file:
            file_handler = logging.FileHandler(log_file, mode="a")
            file_handler.setLevel(logging.DEBUG)
            file_handler.setFormatter(
                logging.Formatter(LOG_FORMAT, datefmt=LOG_DATEFMT)
            )
            root.addHandler(file_handler)

        _CONFIGURED = True

    return logging.getLogger(name)


@contextmanager
def step(
    logger: logging.Logger, description: str
) -> Generator[None, None, None]:
    """Context manager that logs start/end and elapsed time of an operation."""
    logger.info("%s ...", description)
    t0 = time.perf_counter()
    try:
        yield
    except Exception:
        elapsed = time.perf_counter() - t0
        logger.error("%s FAILED after %.1fs", description, elapsed)
        raise
    elapsed = time.perf_counter() - t0
    logger.info("%s done (%.1fs)", description, elapsed)


def log_dataframe_info(
    logger: logging.Logger,
    df,
    name: str,
    *,
    show_columns: bool = False,
) -> None:
    """Log shape and memory usage of a DataFrame."""
    mem = df.memory_usage(deep=True).sum()
    units = [("GB", 1 << 30), ("MB", 1 << 20), ("KB", 1 << 10)]
    for label, threshold in units:
        if mem >= threshold:
            mem_str = f"{mem / threshold:.1f} {label}"
            break
    else:
        mem_str = f"{mem} B"
    logger.info(
        "%s: %s rows x %d cols (%s)",
        name,
        f"{len(df):,}",
        len(df.columns),
        mem_str,
    )
    if show_columns:
        logger.debug("%s columns: %s", name, ", ".join(df.columns))


def log_cohort_filter(
    logger: logging.Logger,
    description: str,
    before: int,
    after: int,
) -> None:
    """Log a cohort filtering step with before/after counts."""
    dropped = before - after
    pct = dropped / before * 100 if before > 0 else 0.0
    logger.info(
        "  filter [%s]: %s -> %s (dropped %s, %.1f%%)",
        description,
        f"{before:,}",
        f"{after:,}",
        f"{dropped:,}",
        pct,
    )


def log_separator(logger: logging.Logger) -> None:
    """Log a visual separator line for summary sections."""
    logger.info("=" * 60)


def log_data_profile(
    logger: logging.Logger,
    df,
    name: str,
    *,
    max_categories: int = 8,
) -> None:
    """Log a concise structural profile of a DataFrame.

    Shows shape, memory, per-column dtype + null% + a compact value summary
    (numeric: min/median/max; categorical: top values; datetime: range).
    Designed to make gz/parquet data understandable from logs alone.
    """
    import numpy as np

    mem = df.memory_usage(deep=True).sum()
    for label, threshold in [("GB", 1 << 30), ("MB", 1 << 20), ("KB", 1 << 10)]:
        if mem >= threshold:
            mem_str = f"{mem / threshold:.1f} {label}"
            break
    else:
        mem_str = f"{mem} B"

    logger.info("── %s: %s rows × %d cols (%s) ──", name, f"{len(df):,}",
                len(df.columns), mem_str)

    lines: list[str] = []
    for col in df.columns:
        s = df[col]
        dtype = str(s.dtype)
        null_pct = s.isna().mean() * 100
        nuniq = s.nunique()
        null_tag = f"null:{null_pct:.0f}%" if null_pct > 0 else "no nulls"

        if np.issubdtype(s.dtype, np.number):
            desc = s.describe()
            summary = (f"min={desc['min']:.4g}  med={desc['50%']:.4g}  "
                       f"max={desc['max']:.4g}  uniq={nuniq}")
        elif np.issubdtype(s.dtype, np.datetime64):
            summary = f"{s.min()} → {s.max()}"
        elif s.dtype == object or str(s.dtype) == "string":
            top = s.value_counts().head(max_categories)
            top_str = ", ".join(f"{v}({c})" for v, c in top.items())
            if nuniq > max_categories:
                top_str += f" … +{nuniq - max_categories} more"
            summary = top_str
        else:
            summary = f"uniq={nuniq}"

        lines.append(f"  {col:<28s} {dtype:<12s} {null_tag:<12s} {summary}")

    logger.info("  %-28s %-12s %-12s %s", "COLUMN", "DTYPE", "NULLS", "SUMMARY")
    for line in lines:
        logger.info(line)
