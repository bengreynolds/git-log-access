use chrono::{DateTime, Local, Utc};

/// Format timestamp for log entries
/// Returns timestamp in ISO 8601 format: YYYY-MM-DD HH:MM:SS
pub fn format_timestamp() -> String {
    Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

/// Format UTC timestamp for log entries
pub fn format_utc_timestamp() -> String {
    Utc::now().format("%Y-%m-%d %H:%M:%S UTC").to_string()
}

/// Parse timestamp from log entry
pub fn parse_timestamp(timestamp_str: &str) -> Option<DateTime<Local>> {
    // Try local format first
    if let Ok(dt) = DateTime::parse_from_str(timestamp_str, "%Y-%m-%d %H:%M:%S %z") {
        return Some(dt.with_timezone(&Local));
    }
    
    // Try without timezone (assume local)
    if let Ok(naive_dt) = chrono::NaiveDateTime::parse_from_str(timestamp_str, "%Y-%m-%d %H:%M:%S") {
        return Some(Local.from_local_datetime(&naive_dt).single()?);
    }
    
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_timestamp() {
        let timestamp = format_timestamp();
        assert!(timestamp.len() >= 19); // YYYY-MM-DD HH:MM:SS
        assert!(timestamp.contains("-"));
        assert!(timestamp.contains(" "));
        assert!(timestamp.contains(":"));
    }

    #[test]
    fn test_parse_timestamp() {
        let timestamp_str = "2026-03-26 14:32:15";
        let parsed = parse_timestamp(timestamp_str);
        assert!(parsed.is_some());
        
        let dt = parsed.unwrap();
        assert_eq!(dt.format("%Y-%m-%d %H:%M:%S").to_string(), timestamp_str);
    }

    #[test]
    fn test_format_utc_timestamp() {
        let timestamp = format_utc_timestamp();
        assert!(timestamp.len() >= 23); // YYYY-MM-DD HH:MM:SS UTC
        assert!(timestamp.contains("UTC"));
    }
}