package datyx.training;

import java.io.IOException;
import java.sql.SQLException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ai.djl.MalformedModelException;
import ai.djl.translate.TranslateException;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.datasource.DataSource.DatabaseAccess;
import jakarta.annotation.PreDestroy;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

/**
 * Inference with a DeepAR model (a training run's): the series' rows read
 * from the source as they are, each series laid out as the run laid it out
 * (its categories coded as then: a value the model never saw is unknown),
 * and forecast from its end, step by step over the horizon: the mean and
 * the 10th, 50th and 90th percentiles of 100 sample paths. Asked for series
 * by their key, it forecasts those; asked for none, every series still
 * observed, the highest first. A network is loaded from the run once and
 * kept (the latest 8).
 */
@ApplicationScoped
public class DeepArInference {

    @Inject
    ObjectMapper json;

    private final Map<Long, DeepArTrainer.Forecaster> forecasters = new LinkedHashMap<>();

    /** A run's network, ready to forecast: when it was trained, and what it was trained on. */
    public record Model(long runId, Instant trainedAt, DeepArTrainer.Result result, DeepArTrainer.Forecaster forecaster) {
    }

    /**
     * The model of a run that succeeded, in its transaction (the model is
     * read lazily); an IllegalStateException when the run kept too little to
     * forecast with.
     */
    public Model model(TrainingRun run) throws IOException, MalformedModelException {
        DeepArTrainer.Result result = json.readValue(run.results, DeepArTrainer.Result.class);
        if (result.spec() == null || result.categories() == null || result.freq() == null) {
            throw new IllegalStateException("model " + run.id + " was trained before datyx kept what forecasting needs: train it again");
        }
        synchronized (forecasters) {
            DeepArTrainer.Forecaster forecaster = forecasters.get(run.id);
            if (forecaster == null) {
                forecaster = new DeepArTrainer.Forecaster(result, run.model);
                if (forecasters.size() >= Inference.CACHED_MODELS) {
                    Long oldest = forecasters.keySet().iterator().next();
                    DeepArTrainer.Forecaster evicted = forecasters.remove(oldest);
                    synchronized (evicted) {
                        evicted.close();
                    }
                }
                forecasters.put(run.id, forecaster);
            }
            return new Model(run.id, run.finishedAt, result, forecaster);
        }
    }

    @PreDestroy
    void close() {
        synchronized (forecasters) {
            forecasters.values().forEach(DeepArTrainer.Forecaster::close);
            forecasters.clear();
        }
    }

    /**
     * Forecasts {@code series} (each a map of the SeriesKey's columns to
     * values) with {@code model}, in the order asked, a series without rows
     * noted as such; or, for none, the series still observed, the highest
     * first, at most {@code limit}. An IllegalArgumentException says what a
     * series lacks, or that there are too many.
     */
    public List<Inference.Prediction> predict(Model model, DatabaseAccess access, List<Map<String, String>> series, int limit)
            throws SQLException, TranslateException {
        var spec = model.result().spec();
        DeepArData.Builder builder = new DeepArData.Builder(spec, model.result().categories());
        List<List<String>> keys = new ArrayList<>();
        boolean all = series == null || series.isEmpty();
        if (all) {
            TableReader.read(access, spec, builder);
        } else {
            if (series.size() > Inference.MAX_SERIES) {
                throw new IllegalArgumentException("at most " + Inference.MAX_SERIES + " series a call, not " + series.size());
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
        List<DeepArData.Item> items = builder.rows() == 0 ? List.of() : builder.build().items;
        if (all) {
            long latest = items.stream().mapToLong(DeepArData.Item::end).max().orElse(Long.MIN_VALUE);
            items = items.stream().filter(i -> i.end() == latest).toList();
        }
        List<DeepArTrainer.Band> bands;
        synchronized (model.forecaster()) {
            bands = model.forecaster().forecast(items, 0);
        }
        int h = model.result().horizon();
        List<Inference.Prediction> scored = new ArrayList<>();
        for (int i = 0; i < items.size(); i++) {
            DeepArData.Item item = items.get(i);
            DeepArTrainer.Band band = bands.get(i);
            List<DeepArTrainer.Step> steps = new ArrayList<>();
            for (int k = 0; k < band.mean().length; k++) {
                steps.add(new DeepArTrainer.Step(DeepArData.time(model.result().step(), item.end() + k).toString(),
                    DeepArTrainer.round(band.mean()[k]), band.p10()[k], band.p50()[k], band.p90()[k]));
            }
            scored.add(new Inference.Prediction(item.series(), DeepArTrainer.round(DeepArTrainer.sum(band.mean())),
                DeepArTrainer.round(DeepArTrainer.lastSum(item.target(), h)), null, steps));
        }
        if (all) {
            scored.sort(Comparator.comparingDouble(Inference.Prediction::predicted).reversed());
            return scored.size() > limit ? List.copyOf(scored.subList(0, limit)) : scored;
        }
        Map<Map<String, String>, Inference.Prediction> found = new HashMap<>();
        scored.forEach(p -> found.put(p.series(), p));
        List<Inference.Prediction> predictions = new ArrayList<>();
        for (List<String> key : keys) {
            Map<String, String> s = new LinkedHashMap<>();
            for (int k = 0; k < key.size(); k++) {
                s.put(spec.seriesKey().get(k), key.get(k));
            }
            Inference.Prediction p = found.get(s);
            predictions.add(p != null ? p : new Inference.Prediction(s, null, null, "no rows for this series"));
        }
        return predictions;
    }
}
