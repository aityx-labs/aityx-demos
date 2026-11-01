package datyx.training;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Random;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.TimeSeries;
import org.junit.jupiter.api.Test;

/** XGBoost's dataset from a tagged group, and training on it, with XGBoost4J's native library; no server. */
class XgbTrainerTest {

    private final ObjectMapper json = new ObjectMapper();

    /** A patient_days-like group: a visit's hours each day, per run and person, with sex and age; 7 days ahead. */
    private TimeSeries.Spec spec(String horizon, String missing) throws Exception {
        JsonNode table = json.readTree("""
            {"name":"patient_days","databaseSchema":{"name":"public"},
             "tags":[{"tagFQN":"TimeSeries.care.XGBoost"}],
             "columns":[
              {"name":"run_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.SeriesKey"}]},
              {"name":"person_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.SeriesKey"}]},
              {"name":"day","dataType":"DATE","tags":[{"tagFQN":"TimeSeries.care.Timestamp"}]},
              {"name":"sex","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.StaticCategorical"}]},
              {"name":"age","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.StaticReal"}]},
              {"name":"visits","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.PastCovariate"}]},
              {"name":"stay_hours","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.Target"}]}],
             "extension":{"timeSeriesFrequency":"1D","timeSeriesMissing":"%s","timeSeriesHorizon":"%s"}}
            """.formatted(missing, horizon));
        return TimeSeries.spec(table, "care");
    }

    /**
     * 60 people over 300 days: the chronic ones (a third) come every 14 days
     * for 2 hours, everyone now and then for an hour; a visit is a row, a
     * day without one has none. The last person's last visit is early, so
     * their series ends with quiet days counted as zero.
     */
    private Dataset.Builder patients(TimeSeries.Spec spec) {
        Dataset.Builder b = new Dataset.Builder(spec);
        Random random = new Random(3);
        long day0 = LocalDate.of(2026, 1, 1).atStartOfDay().toEpochSecond(ZoneOffset.UTC);
        for (int p = 0; p < 60; p++) {
            boolean chronic = p % 3 == 0;
            int phase = random.nextInt(14);
            for (int d = 0; d < 300; d++) {
                double hours = (chronic && d % 14 == phase ? 2 : 0) + (random.nextDouble() < 0.02 ? 1 : 0);
                if (p == 59 && d > 40) {
                    hours = 0;
                }
                if (hours > 0 || (d == 0)) {
                    b.add(new Dataset.Row(day0 + d * 86_400L, List.of("r1", "p" + p), new String[] {p % 2 == 0 ? "woman" : "man"},
                        new double[] {20 + p}, hours, new double[] {hours > 0 ? 1 : 0}, new double[0]));
                }
            }
        }
        return b;
    }

    @Test
    void makesExamplesFromTheTagsAndSplitsThemByTime() throws Exception {
        Dataset data = patients(spec("7D", "zero")).build();
        assertEquals(60, data.summary.series());
        assertEquals(60 * 300, data.summary.steps(), "every series runs to its run's last day");
        assertEquals(List.of("sex", "age", "steps of history", "steps since stay_hours > 0",
            "stay_hours, last 1D", "stay_hours, last 7D", "stay_hours, last 21D", "stay_hours, last 84D",
            "visits, last 1D", "visits, last 7D", "visits, last 21D", "visits, last 84D"), data.featureNames);
        assertEquals("c", data.featureTypes[0]);
        assertEquals(1, data.summary.stride(), "a quarter of a 7-day horizon, at least a step");
        assertEquals(data.summary.examples(), 60 * (300 - 7));
        assertTrue(data.train.rows() > data.test.rows() && data.test.rows() > 0 && data.valid.rows() > 0);
        assertEquals(60, data.scored.size(), "all of them are still observed");
        assertEquals("2026-10-28T00:00", data.summary.scoredAt());
    }

    @Test
    void xgboostLearnsTheVisitsRhythmBetterThanRepeatingTheLastWeek() throws Exception {
        XgbTrainer.Trained trained = XgbTrainer.train(patients(spec("7D", "zero")).build());
        XgbTrainer.Metrics test = trained.result().test();
        assertTrue(test.mae() < test.naiveMae(), test.toString());
        assertTrue(test.improvement() > 0.2, test.toString());
        assertEquals("count:poisson", trained.result().params().get("objective"));
        assertTrue(trained.model().length > 1000);
        assertTrue(trained.result().importance().stream().anyMatch(i -> i.feature().equals("steps since stay_hours > 0")),
            trained.result().importance().toString());
        assertEquals(25, trained.result().scores().size());
        XgbTrainer.Score top = trained.result().scores().get(0);
        assertEquals("r1", top.series().get("run_id"));
        assertTrue(top.predicted() >= trained.result().scores().get(24).predicted());
    }

    @Test
    void saysWhyItCantTrain() throws Exception {
        assertEquals("the horizon 36h isn't a whole number of steps of 1D",
            assertThrows(IllegalArgumentException.class, () -> new Dataset.Builder(spec("36h", "zero"))).getMessage());
        Dataset.Builder few = new Dataset.Builder(spec("7D", "zero"));
        few.add(new Dataset.Row(0, List.of("r1", "p1"), new String[] {"man"}, new double[] {30}, 1, new double[] {1},
            new double[0]));
        assertTrue(assertThrows(IllegalArgumentException.class, few::build).getMessage().startsWith("no series is longer"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new Dataset.Builder(spec("30D", "zero")).build())
            .getMessage().startsWith("the table has no rows"));
    }

    @Test
    void unknownStepsAreGapsNotZeros() throws Exception {
        // A row every day but for ten, with missing rows unknown: no label
        // spans the gap, and the series ends at its own last row.
        Dataset.Builder b = new Dataset.Builder(spec("7D", "unknown"));
        for (int p = 0; p < 20; p++) {
            for (int d = 0; d < 200; d++) {
                if (p == 0 && d >= 100 && d < 110) {
                    continue;
                }
                b.add(new Dataset.Row(d * 86_400L, List.of("r1", "p" + p), new String[] {"man"}, new double[] {40},
                    d % 7 == p % 7 ? 2 : 0, new double[] {0}, new double[0]));
            }
        }
        Dataset data = b.build();
        int full = 20 * (200 - 7);
        int spanningTheGap = 10 + 7 - 1;
        assertEquals(full - spanningTheGap, data.summary.examples());
    }
}
