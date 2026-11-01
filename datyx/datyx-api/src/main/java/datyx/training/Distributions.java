package datyx.training;

import java.util.SplittableRandom;

import ai.djl.ndarray.NDArray;
import ai.djl.ndarray.NDList;
import ai.djl.ndarray.types.Shape;
import ai.djl.timeseries.distribution.Distribution;
import ai.djl.timeseries.distribution.NegativeBinomial;
import ai.djl.timeseries.distribution.StudentT;
import ai.djl.timeseries.distribution.output.DistributionOutput;
import ai.djl.timeseries.distribution.output.StudentTOutput;
import ai.djl.util.PairList;

/**
 * DeepAR's distributions, as DJL's (the same arguments, so the same
 * parameters, the same likelihood and mean), but sampled here, in Java: DJL
 * samples a negative binomial (Gamma, then Poisson) and a Student's t
 * (Gamma, then normal) with ops its PyTorch engine doesn't have, so its
 * forecasts can't draw their paths. The draws are a few hundred numbers a
 * step, read from the network's arguments and handed back as an array.
 */
final class Distributions {

    private Distributions() {
    }

    private static final ThreadLocal<SplittableRandom> RANDOM = ThreadLocal.withInitial(SplittableRandom::new);

    /** Seeds this thread's draws, so a test's forecasts repeat. */
    static void seed(long seed) {
        RANDOM.set(new SplittableRandom(seed));
    }

    /** DJL's NegativeBinomialOutput (final, so copied): a count's total_count and logits. */
    static final class CountOutput extends DistributionOutput {

        CountOutput() {
            argsDim = new PairList<>(2);
            argsDim.add("total_count", 1);
            argsDim.add("logits", 1);
        }

        @Override
        public NDList domainMap(NDList arrays) {
            NDArray totalCount = arrays.get(0).getNDArrayInternal().softPlus().squeeze(-1);
            NDArray logits = arrays.get(1).squeeze(-1);
            totalCount.setName("total_count");
            logits.setName("logits");
            return new NDList(totalCount, logits);
        }

        @Override
        public Distribution.DistributionBuilder<?> distributionBuilder() {
            return new CountBuilder();
        }
    }

    private static final class CountBuilder extends Distribution.DistributionBuilder<CountBuilder> {

        @Override
        public Distribution build() {
            Distribution djl = NegativeBinomial.builder().setDistrArgs(distrArgs).optScale(scale).build();
            return new Count(djl, distrArgs.get("total_count"), distrArgs.get("logits"));
        }

        @Override
        protected CountBuilder self() {
            return this;
        }
    }

    /**
     * A negative binomial: a Poisson whose rate is Gamma(total_count,
     * exp(logits)), as DJL's (which applies no scale to the logits: the
     * network learns counts as they are).
     */
    private static final class Count extends Distribution {

        private final Distribution djl;
        private final NDArray totalCount;
        private final NDArray logits;

        Count(Distribution djl, NDArray totalCount, NDArray logits) {
            this.djl = djl;
            this.totalCount = totalCount;
            this.logits = logits;
        }

        @Override
        public NDArray logProb(NDArray target) {
            return djl.logProb(target);
        }

        @Override
        public NDArray mean() {
            return djl.mean();
        }

        @Override
        public NDArray sample(int numSamples) {
            float[] r = totalCount.toFloatArray();
            float[] l = logits.toFloatArray();
            int copies = Math.max(1, numSamples);
            float[] out = new float[r.length * copies];
            SplittableRandom random = RANDOM.get();
            for (int c = 0; c < copies; c++) {
                for (int i = 0; i < r.length; i++) {
                    double rate = gamma(random, r[i], Math.exp(l[i]));
                    out[c * r.length + i] = poisson(random, Math.min(rate, 1e9));
                }
            }
            return totalCount.getManager().create(out, numSamples > 0
                ? new Shape(numSamples).addAll(totalCount.getShape()) : totalCount.getShape());
        }
    }

    /** DJL's StudentTOutput, its distribution sampled here. */
    static final class RealOutput extends StudentTOutput {

        @Override
        public Distribution.DistributionBuilder<?> distributionBuilder() {
            return new RealBuilder();
        }
    }

    private static final class RealBuilder extends Distribution.DistributionBuilder<RealBuilder> {

        @Override
        public Distribution build() {
            Distribution djl = StudentT.builder().setDistrArgs(distrArgs).optScale(scale).optLoc(loc).build();
            return new Real(djl, distrArgs.get("mu"), distrArgs.get("sigma"), distrArgs.get("nu"), loc, scale);
        }

        @Override
        protected RealBuilder self() {
            return this;
        }
    }

    /** A Student's t, shifted by loc and stretched by scale when given: mu + sigma * Z / sqrt(G / nu), G chi-squared. */
    private static final class Real extends Distribution {

        private final Distribution djl;
        private final NDArray mu;
        private final NDArray sigma;
        private final NDArray nu;
        private final NDArray loc;
        private final NDArray scale;

        Real(Distribution djl, NDArray mu, NDArray sigma, NDArray nu, NDArray loc, NDArray scale) {
            this.djl = djl;
            this.mu = mu;
            this.sigma = sigma;
            this.nu = nu;
            this.loc = loc;
            this.scale = scale;
        }

        @Override
        public NDArray logProb(NDArray target) {
            return djl.logProb(target);
        }

        @Override
        public NDArray mean() {
            return djl.mean();
        }

        @Override
        public NDArray sample(int numSamples) {
            float[] m = mu.toFloatArray();
            float[] s = sigma.toFloatArray();
            float[] n = nu.toFloatArray();
            float[] shift = loc == null ? null : loc.toFloatArray();
            float[] stretch = scale == null ? null : scale.toFloatArray();
            int copies = Math.max(1, numSamples);
            float[] out = new float[m.length * copies];
            SplittableRandom random = RANDOM.get();
            for (int c = 0; c < copies; c++) {
                for (int i = 0; i < m.length; i++) {
                    double t = m[i] + s[i] * normal(random) / Math.sqrt(gamma(random, n[i] / 2, 2) / n[i]);
                    double a = stretch == null ? 1 : stretch[broadcast(i, m.length, stretch.length)];
                    double b = shift == null ? 0 : shift[broadcast(i, m.length, shift.length)];
                    out[c * m.length + i] = (float) (b + a * t);
                }
            }
            return mu.getManager().create(out, numSamples > 0
                ? new Shape(numSamples).addAll(mu.getShape()) : mu.getShape());
        }
    }

    /** Which of {@code size} values (one, one per row, or one each) goes with the i-th of {@code length}. */
    private static int broadcast(int i, int length, int size) {
        if (size == length) {
            return i;
        }
        if (size == 1) {
            return 0;
        }
        return i / (length / size);
    }

    static double normal(SplittableRandom random) {
        double u;
        double v;
        double s;
        do {
            u = random.nextDouble() * 2 - 1;
            v = random.nextDouble() * 2 - 1;
            s = u * u + v * v;
        } while (s >= 1 || s == 0);
        return u * Math.sqrt(-2 * Math.log(s) / s);
    }

    /** A Gamma(shape, scale) draw: Marsaglia and Tsang's, boosted below a shape of one. */
    static double gamma(SplittableRandom random, double shape, double scale) {
        if (!(shape > 0) || !(scale > 0)) {
            return 0;
        }
        if (shape < 1) {
            return gamma(random, shape + 1, scale) * Math.pow(random.nextDouble(), 1 / shape);
        }
        double d = shape - 1.0 / 3;
        double c = 1 / Math.sqrt(9 * d);
        while (true) {
            double x = normal(random);
            double v = 1 + c * x;
            if (v <= 0) {
                continue;
            }
            v = v * v * v;
            double u = random.nextDouble();
            if (Math.log(u) < 0.5 * x * x + d - d * v + d * Math.log(v)) {
                return d * v * scale;
            }
        }
    }

    /** A Poisson(rate) draw: Knuth's below 30, the normal approximation above. */
    static float poisson(SplittableRandom random, double rate) {
        if (!(rate > 0)) {
            return 0;
        }
        if (rate >= 30) {
            return (float) Math.max(0, Math.rint(rate + Math.sqrt(rate) * normal(random)));
        }
        double limit = Math.exp(-rate);
        double p = random.nextDouble();
        int k = 0;
        while (p > limit) {
            p *= random.nextDouble();
            k++;
        }
        return k;
    }
}
