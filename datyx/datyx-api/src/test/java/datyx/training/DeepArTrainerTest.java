package datyx.training;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Random;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.TimeSeries;
import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * DeepAR's series from a tagged group, and training on them, with DJL's
 * PyTorch engine. A Quarkus test, though it needs no server: libtorch loads
 * once a JVM, in one class loader, and the other tests load it in Quarkus's.
 */
@QuarkusTest
class DeepArTrainerTest {

    private final ObjectMapper json = new ObjectMapper();

    /** An admissions_hourly-like group: admissions per run, hospital and hour, the hospital a category. */
    private TimeSeries.Spec spec(String horizon) throws Exception {
        JsonNode table = json.readTree("""
            {"name":"admissions_hourly","databaseSchema":{"name":"public"},
             "columns":[
              {"name":"run_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.SeriesKey"}]},
              {"name":"hospital_id","dataType":"INT","tags":[{"tagFQN":"TimeSeries.SeriesKey"},
                {"tagFQN":"TimeSeries.StaticCategorical"}]},
              {"name":"hour_start","dataType":"TIMESTAMP","tags":[{"tagFQN":"TimeSeries.Timestamp"}]},
              {"name":"admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.Target"}]}],
             "extension":{"timeSeriesFrequency":"1h","timeSeriesMissing":"zero"%s}}
            """.formatted(horizon == null ? "" : ",\"timeSeriesHorizon\":\"" + horizon + "\""));
        return TimeSeries.spec(table, TimeSeries.DEFAULT_GROUP);
    }

    private static final long HOUR0 = LocalDateTime.of(2026, 1, 1, 0, 0).toEpochSecond(ZoneOffset.UTC);

    /**
     * Six hospitals over {@code days} days: admissions from 8:00 to 17:59
     * at a rate of 0.8 an hour (twice that at the first hospital), 0.05 at
     * night; an hour without one has no row. The run's last row is the
     * last hour of its last day, at hospital 1.
     */
    private <R extends Rows> R hospitals(R rows, int days) {
        Random random = new Random(7);
        for (int hospital = 1; hospital <= 6; hospital++) {
            for (int hour = 0; hour < days * 24; hour++) {
                int of = hour % 24;
                double rate = (of >= 8 && of < 18 ? 0.8 : 0.05) * (hospital == 1 ? 2 : 1);
                int n = poisson(random, rate);
                if (n > 0 || (hospital == 1 && hour == days * 24 - 1)) {
                    rows.add(new Dataset.Row(HOUR0 + hour * 3600L, List.of("r1", String.valueOf(hospital)),
                        new String[] {String.valueOf(hospital)}, new double[0], n, new double[0], new double[0]));
                }
            }
        }
        return rows;
    }

    private static int poisson(Random random, double rate) {
        double l = Math.exp(-rate);
        double p = random.nextDouble();
        int k = 0;
        while (p > l) {
            p *= random.nextDouble();
            k++;
        }
        return k;
    }

    @Test
    void seriesFromAGroup() throws Exception {
        DeepArData data = hospitals(new DeepArData.Builder(spec(null)), 3).build();
        assertEquals("H", data.freq);
        assertEquals(3600, data.step);
        assertEquals(DeepArData.DEFAULT_HORIZON, data.horizon, "no horizon: 24 steps");
        assertEquals(6, data.items.size());
        assertEquals(List.of(7), data.cardinality(), "six hospitals and one code for a hospital never seen");
        for (DeepArData.Item item : data.items) {
            // Every hospital runs to the cohort's end, the run's last hour, its quiet hours zero.
            assertEquals(HOUR0 / 3600 + 72, item.end(), item.series().toString());
        }
        assertEquals("2026-01-01T00:00", data.time(HOUR0 / 3600).toString());
        assertEquals(12, hospitals(new DeepArData.Builder(spec("12h")), 3).build().horizon, "the table's horizon, in steps");
    }

    @Test
    void aHorizonThatIsntWholeSteps() throws Exception {
        assertThrows(IllegalArgumentException.class, () -> new DeepArData.Builder(spec("90min")));
    }

    @Test
    void codesAsAModelWasTrained() throws Exception {
        DeepArData trained = hospitals(new DeepArData.Builder(spec(null)), 3).build();
        DeepArData.Builder later = new DeepArData.Builder(spec(null), trained.categories);
        later.add(new Dataset.Row(HOUR0, List.of("r2", "9"), new String[] {"9"}, new double[0], 1, new double[0],
            new double[0]));
        later.add(new Dataset.Row(HOUR0, List.of("r2", "2"), new String[] {"2"}, new double[0], 1, new double[0],
            new double[0]));
        List<DeepArData.Item> items = later.build().items;
        assertArrayEquals(new int[] {0}, items.get(0).categories(), "a hospital the model never saw");
        assertEquals(trained.categories.get("hospital_id").get("2"), items.get(1).categories()[0]);
    }

    @Test
    void tooShortToLearn() throws Exception {
        DeepArData data = hospitals(new DeepArData.Builder(spec("2D")), 3).build();
        IllegalArgumentException e = assertThrows(IllegalArgumentException.class,
            () -> DeepArTrainer.train(data, 1, Duration.ofMinutes(1), 1));
        assertTrue(e.getMessage().contains("twice the horizon"), e.getMessage());
    }

    /** DeepAR learns the day's rhythm: better than repeating the last day, busier by day, at the busier hospital. */
    @Test
    void learnsTheDaysRhythm() throws Exception {
        DeepArData data = hospitals(new DeepArData.Builder(spec(null)), 40).build();
        DeepArTrainer.Trained trained = DeepArTrainer.train(data, 12, Duration.ofMinutes(3), 1);
        DeepArTrainer.Result r = trained.result();
        assertTrue(trained.model().length > 10_000, "the network's parameters");
        assertEquals("negative binomial", r.distribution());
        assertEquals(6 * 24, r.test().examples(), "every hospital's held-out day");
        assertTrue(r.test().mae() < r.test().naiveMae(), "better than the last day: " + r.test());
        assertTrue(r.coverage() > 0.6, "the 10th to 90th percentiles hold most hours: " + r.coverage());
        assertEquals(6, r.scores().size(), "every hospital is still observed");
        assertEquals("1", r.scores().get(0).series().get("hospital_id"), "the busiest first: " + r.scores());

        // Forecast again from the kept parameters: the next day, from midnight, busier from 8:00 to 17:59.
        try (DeepArTrainer.Forecaster f = new DeepArTrainer.Forecaster(r, trained.model())) {
            DeepArData.Item hospital1 = data.items.get(0);
            DeepArTrainer.Band forecast = f.forecast(List.of(hospital1), 0).get(0);
            float[] mean = forecast.mean();
            float[] low = forecast.p10();
            float[] median = forecast.p50();
            float[] high = forecast.p90();
            assertEquals(24, mean.length);
            double day = 0;
            double night = 0;
            for (int k = 0; k < 24; k++) {
                // Counts: whole percentiles, in order (a skewed mean may pass the 90th at a quiet hour).
                assertTrue(low[k] <= median[k] && median[k] <= high[k] && median[k] == Math.rint(median[k]), "k=" + k);
                if (k >= 8 && k < 18) {
                    day += mean[k] / 10;
                } else {
                    night += mean[k] / 14;
                }
            }
            assertTrue(day > 3 * night, "by day " + day + ", by night " + night);
        }
    }
}
