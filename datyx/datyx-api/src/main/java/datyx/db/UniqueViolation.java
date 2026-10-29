package datyx.db;

import java.sql.SQLException;

/** Whether PostgreSQL refused a row for a unique index or constraint (SQLSTATE 23505). */
public final class UniqueViolation {

    private UniqueViolation() {
    }

    public static boolean in(Throwable e) {
        for (Throwable cause = e; cause != null; cause = cause.getCause()) {
            if (cause instanceof SQLException sql && "23505".equals(sql.getSQLState())) {
                return true;
            }
        }
        return false;
    }
}
