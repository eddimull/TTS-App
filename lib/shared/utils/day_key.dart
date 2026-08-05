/// Normalises [dt] to midnight of its calendar day, for use as a `Map` key
/// (or equality check) when grouping items by day. Strips time-of-day so two
/// [DateTime]s on the same date compare equal regardless of hour/minute/etc.
DateTime dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
