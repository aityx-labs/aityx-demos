package datyx.catalog;

import java.time.Duration;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * A span of time of a fixed length, written as a pandas offset with a
 * count: 30min, 1h, 6h, 1D, 30D, 1W ("D" alone is one day). The ones whose
 * length varies (a month, a business day, a quarter) aren't spans: what
 * datyx counts in steps (a horizon, a retraining interval) needs a length.
 */
public record Span(long count, String unit) {

    private static final Pattern PATTERN = Pattern.compile("(\\d*)(min|h|D|W)");

    /** The span a text names, or null when it names none of a fixed length. */
    public static Span parse(String text) {
        if (text == null) {
            return null;
        }
        Matcher m = PATTERN.matcher(text.strip());
        if (!m.matches()) {
            return null;
        }
        long count = m.group(1).isEmpty() ? 1 : Long.parseLong(m.group(1));
        return count > 0 && count <= 100_000 ? new Span(count, m.group(2)) : null;
    }

    public Duration duration() {
        return switch (unit) {
            case "min" -> Duration.ofMinutes(count);
            case "h" -> Duration.ofHours(count);
            case "D" -> Duration.ofDays(count);
            default -> Duration.ofDays(7 * count);
        };
    }

    /** A duration as the shortest span that says it: 30D, 6h, 1W. */
    public static String of(Duration duration) {
        long minutes = duration.toMinutes();
        if (minutes % (7 * 24 * 60) == 0) {
            return minutes / (7 * 24 * 60) + "W";
        }
        if (minutes % (24 * 60) == 0) {
            return minutes / (24 * 60) + "D";
        }
        if (minutes % 60 == 0) {
            return minutes / 60 + "h";
        }
        return minutes + "min";
    }

    @Override
    public String toString() {
        return count + unit;
    }
}
