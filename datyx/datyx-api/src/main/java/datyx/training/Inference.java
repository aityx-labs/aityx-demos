package datyx.training;

import java.io.IOException;
import java.sql.SQLException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.datasource.DataSource.DatabaseAccess;
import io.quarkus.runtime.annotations.RegisterForReflection;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import ml.dmlc.xgboost4j.java.Booster;
import ml.dmlc.xgboost4j.java.DMatrix;
import ml.dmlc.xgboost4j.java.XGBoost;
import ml.dmlc.xgboost4j.java.XGBoostError;

/**
 * Inference: a model datyx trained (a training run's) scoring series now.
 * The series' rows are read from the source as they are, their features
 * built as the run built them (the group as it was trained, its
 * categories' codes: a value the model never saw is missing), and the
 * model, loaded from the run once and kept, predicts the Target summed
 * over the horizon ahead. Asked for series by their key, it scores those;
 * asked for none, every series still observed, the highest first.
 */
@ApplicationScoped
public class Inference {

    /** The most series one call can name. */
    public static final int MAX_SERIES = 100;

    static final int CACHED_MODELS = 8;

    @Inject
    ObjectMapper json;

    private final Map<Long, Booster> boosters = new ConcurrentHashMap<>();

    /** A run's model, ready to score: when it was trained, and what it was trained on. */
    public record Model(long runId, Instant trainedAt, XgbTrainer.Result result, Booster booster) {
    }

    /** A series scored: its key, the prediction, its Target over the last horizon; or why it wasn't. */
    @RegisterForReflection
    public record Prediction(Map<String, String> series, Double predicted, Double last, String note) {
    }

    /**
     * The model of a run that succeeded, in its transaction (the model is
     * read lazily); an IllegalStateException when the run kept too little to
     * score with (trained before datyx kept the group and codes with it).
     */
    public Model model(TrainingRun run) throws IOException, XGBoostError {
        XgbTrainer.Result result = json.readValue(run.results, XgbTrainer.Result.class);
        if (result.spec() == null || result.categories() == null) {
            throw new IllegalStateException("model " + run.id + " was trained before datyx kept what scoring needs: train it again");
        }
        Booster booster = boosters.get(run.id);
        if (booster == null) {
            booster = XGBoost.loadModel(run.model);
            if (boosters.size() >= CACHED_MODELS) {
                boosters.clear();
            }
            boosters.put(run.id, booster);
        }
        return new Model(run.id, run.finishedAt, result, booster);
    }

    /**
     * Scores {@code series} (each a map of the SeriesKey's columns to values)
     * with {@code model}, in the order asked, a series without rows noted as
     * such; or, for none, the series still observed, the highest first, at
     * most {@code limit}. An IllegalArgumentException says what a series
     * lacks, or that there are too many.
     */
    public List<Prediction> predict(Model model, DatabaseAccess access, List<Map<String, String>> series, int limit)
            throws SQLException, XGBoostError {
        var spec = model.result().spec();
        Dataset.Builder builder = new Dataset.Builder(spec, model.result().categories());
        List<List<String>> keys = new ArrayList<>();
        boolean all = series == null || series.isEmpty();
        if (all) {
            TableReader.read(access, spec, builder);
        } else {
            if (series.size() > MAX_SERIES) {
                throw new IllegalArgumentException("at most " + MAX_SERIES + " series a call, not " + series.size());
            }
            for (Map<String, String> s : series) {
                List<String> key = new ArrayList<>();
                for (String column : spec.seriesKey()) {
                    String v = s == null ? null : s.get(column);
                    if (v == null) {
                        throw new IllegalArgumentException("a series names its key: " + String.join(", ", spec.seriesKey()));
                    }
                    key.add(v);
                }
                keys.add(List.copyOf(key));
            }
            TableReader.read(access, spec, builder, keys);
        }
        List<Dataset.Scored> scored = builder.atEnd();
        if (all) {
            long latest = scored.stream().mapToLong(Dataset.Scored::end).max().orElse(Long.MIN_VALUE);
            scored = scored.stream().filter(s -> s.end() == latest).toList();
        }
        float[][] p = predict(model, scored);
        List<Prediction> predictions = new ArrayList<>();
        if (all) {
            for (int r = 0; r < scored.size(); r++) {
                predictions.add(new Prediction(scored.get(r).series(), round(p[r][0]), round(scored.get(r).last()), null));
            }
            predictions.sort(Comparator.comparingDouble(Prediction::predicted).reversed());
            return predictions.size() > limit ? List.copyOf(predictions.subList(0, limit)) : predictions;
        }
        Map<Map<String, String>, Integer> found = new HashMap<>();
        for (int r = 0; r < scored.size(); r++) {
            found.put(scored.get(r).series(), r);
        }
        for (List<String> key : keys) {
            Map<String, String> s = new java.util.LinkedHashMap<>();
            for (int k = 0; k < key.size(); k++) {
                s.put(spec.seriesKey().get(k), key.get(k));
            }
            Integer r = found.get(s);
            predictions.add(r == null ? new Prediction(s, null, null, "no rows for this series")
                : new Prediction(s, round(p[r][0]), round(scored.get(r).last()), null));
        }
        return predictions;
    }

    private static float[][] predict(Model model, List<Dataset.Scored> scored) throws XGBoostError {
        if (scored.isEmpty()) {
            return new float[0][];
        }
        int n = model.result().features().size();
        float[] x = new float[scored.size() * n];
        for (int r = 0; r < scored.size(); r++) {
            System.arraycopy(scored.get(r).features(), 0, x, r * n, n);
        }
        DMatrix m = new DMatrix(x, scored.size(), n, Float.NaN);
        try {
            m.setFeatureTypes(model.result().featureTypes().toArray(String[]::new));
            synchronized (model.booster()) {
                return model.booster().predict(m);
            }
        } finally {
            m.dispose();
        }
    }

    private static double round(double v) {
        return Math.round(v * 1000) / 1000.0;
    }
}
