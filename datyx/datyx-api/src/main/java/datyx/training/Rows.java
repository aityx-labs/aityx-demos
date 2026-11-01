package datyx.training;

import java.util.List;

/**
 * Where TableReader puts a group's rows: XGBoost's dataset (Dataset.Builder)
 * or DeepAR's series (DeepArData.Builder).
 */
interface Rows {

    void add(Dataset.Row row);

    /** How many rows were added. */
    int rows();

    /**
     * The cohort of a series (its key but the last column) was observed
     * until {@code epochSecond}, which the rows read may not reach.
     */
    void observedUntil(List<String> cohort, long epochSecond);
}
