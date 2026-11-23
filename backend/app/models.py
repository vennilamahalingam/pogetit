"""Request bodies. Timestamps are epoch milliseconds (matches Dart's millisecondsSinceEpoch)."""
from pydantic import BaseModel, Field


class Fix(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracyM: float = Field(ge=0)
    timestamp: int
    isMocked: bool = False


class RouteSummary(BaseModel):
    fixCount: int = Field(default=0, ge=0)       # accepted GPS fixes
    rejectedCount: int = Field(default=0, ge=0)  # dropped for accuracy / jumps
    mockedCount: int = Field(default=0, ge=0)    # fixes flagged isMocked


class StepsEvidence(BaseModel):
    count: int = Field(ge=0)
    windowStart: int
    windowEnd: int


class ProgressRequest(BaseModel):
    distanceM: float = Field(default=0, ge=0)
    steps: int | None = Field(default=None, ge=0)  # None = no step reading this time (keep previous)
    route: RouteSummary | None = None  # saved so fix counts survive an app restart


class ValidateRequest(BaseModel):
    distanceM: float = Field(default=0, ge=0)
    route: RouteSummary = RouteSummary()
    steps: StepsEvidence | None = None  # None = no Health Connect data (never substituted)
    freshFix: Fix
