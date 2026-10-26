

from datetime import date, datetime, timedelta, timezone


ENTRIES = 154

assert ENTRIES < 1000, "ENTRIES must be less than 1000"

today = date.today()
today_yymmdd = today.strftime("%y%m%d")
now_utc = datetime.now(timezone.utc)

today_yymmdd = '261026'

for i in range(1, ENTRIES + 1):
    id = f"MIG{today_yymmdd}{i:03d}"
    assert len(id) == 12, f"ID length is not 12: {id}"
    ts = now_utc + timedelta(seconds=10 * (i - 1))
    ts = f"{ts.isoformat(timespec='milliseconds').replace('+00:00', 'Z')}"
    print(f"{id},{ts}")