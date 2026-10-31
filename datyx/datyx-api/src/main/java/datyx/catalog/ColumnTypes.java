package datyx.catalog;

import java.sql.Types;
import java.util.Locale;
import java.util.Set;

/**
 * A source column's type as OpenMetadata names it (its column dataType
 * enum), from what JDBC reports: the java.sql.Types code first, the
 * database's own type name where the code says too little (PostgreSQL
 * reports text as VARCHAR, timestamptz as TIMESTAMP, json as OTHER).
 */
public final class ColumnTypes {

    /** The OpenMetadata types a time index can be. */
    public static final Set<String> TEMPORAL = Set.of("DATE", "DATETIME", "TIMESTAMP", "TIMESTAMPZ");

    /** The OpenMetadata types a target or a real-valued feature can be. */
    public static final Set<String> NUMERIC = Set.of("TINYINT", "SMALLINT", "INT", "BIGINT", "LONG", "NUMBER",
        "NUMERIC", "DECIMAL", "FLOAT", "DOUBLE", "MONEY", "UINT");

    private ColumnTypes() {
    }

    /** The OpenMetadata dataType of a column: UNKNOWN when nothing fits. */
    public static String of(int jdbcType, String typeName) {
        String name = typeName == null ? "" : typeName.toLowerCase(Locale.ROOT);
        switch (name) {
            case "text", "citext", "name" -> {
                return "TEXT";
            }
            case "timestamptz" -> {
                return "TIMESTAMPZ";
            }
            case "bytea" -> {
                return "BYTEA";
            }
            case "json", "jsonb" -> {
                return "JSON";
            }
            case "uuid" -> {
                return "UUID";
            }
            case "xml" -> {
                return "XML";
            }
            case "inet" -> {
                return "INET";
            }
            case "cidr" -> {
                return "CIDR";
            }
            case "macaddr", "macaddr8" -> {
                return "MACADDR";
            }
            case "interval" -> {
                return "INTERVAL";
            }
            case "money" -> {
                return "MONEY";
            }
            case "bool", "boolean" -> {
                return "BOOLEAN";
            }
            default -> {
            }
        }
        return switch (jdbcType) {
            case Types.BOOLEAN, Types.BIT -> "BOOLEAN";
            case Types.TINYINT -> "TINYINT";
            case Types.SMALLINT -> "SMALLINT";
            case Types.INTEGER -> "INT";
            case Types.BIGINT -> "BIGINT";
            case Types.REAL, Types.FLOAT -> "FLOAT";
            case Types.DOUBLE -> "DOUBLE";
            case Types.NUMERIC -> "NUMERIC";
            case Types.DECIMAL -> "DECIMAL";
            case Types.CHAR, Types.NCHAR -> "CHAR";
            case Types.VARCHAR, Types.NVARCHAR -> "VARCHAR";
            case Types.LONGVARCHAR, Types.LONGNVARCHAR, Types.CLOB, Types.NCLOB -> "TEXT";
            case Types.DATE -> "DATE";
            case Types.TIME, Types.TIME_WITH_TIMEZONE -> "TIME";
            case Types.TIMESTAMP -> "TIMESTAMP";
            case Types.TIMESTAMP_WITH_TIMEZONE -> "TIMESTAMPZ";
            case Types.BINARY -> "BINARY";
            case Types.VARBINARY -> "VARBINARY";
            case Types.LONGVARBINARY, Types.BLOB -> "BLOB";
            case Types.ARRAY -> "ARRAY";
            case Types.STRUCT -> "STRUCT";
            case Types.SQLXML -> "XML";
            default -> "UNKNOWN";
        };
    }

    /** Whether OpenMetadata wants a dataLength with the type. */
    public static boolean hasLength(String dataType) {
        return Set.of("CHAR", "VARCHAR", "BINARY", "VARBINARY").contains(dataType);
    }
}
