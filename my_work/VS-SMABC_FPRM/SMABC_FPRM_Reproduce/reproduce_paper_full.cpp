#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <numeric>
#include <random>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace fs = std::filesystem;

struct Bench {
    std::string name;
    int n = 0;
    uint32_t mask = 0;
    std::vector<uint32_t> on_set; // Full minterms with output=1.
};

struct Params {
    int runs = 20;
    int np = 100;
    int generations = 50;
    int conv_runs = 10;

    int smabc_lc = 3;
    int smabc_ls = 3;
    double smabc_alpha1 = 1.0;
    double smabc_alpha2 = 0.05;
    int smabc_limit = 7;

    double ga_pc = 0.7;
    double ga_pm = 0.03;

    double pso_w = 0.3;
    double pso_c1 = 2.0;
    double pso_c2 = 2.0;

    uint32_t seed = 20260421u;
    int cache_limit = 200000;

    // -----------------------------------------------------------------------
    // Tech-aware gate cost weights (Change 3).
    // Defaults are extracted from NangateOpenCellLibrary_typical.lib (45 nm):
    //   AND2_X1  area = 1.064
    //   XOR2_X1  area = 1.596
    // Configurable via SMABC_C_AND / SMABC_C_XOR environment variables.
    // -----------------------------------------------------------------------
    double c_and = 1.064;
    double c_xor = 1.596;
};

static int popcount_u32(uint32_t x) {
#if defined(__GNUG__) || defined(__clang__)
    return __builtin_popcount(x);
#else
    int c = 0;
    while (x) {
        x &= (x - 1u);
        ++c;
    }
    return c;
#endif
}

static uint32_t rand_polarity(std::mt19937 &rng, uint32_t mask) {
    std::uniform_int_distribution<uint32_t> dist(0u, mask);
    return dist(rng) & mask;
}

static bool parse_int_env(const char *name, int &v) {
    const char *s = std::getenv(name);
    if (!s || !*s) return false;
    try {
        v = std::stoi(s);
        return true;
    } catch (...) {
        return false;
    }
}

static bool parse_double_env(const char *name, double &v) {
    const char *s = std::getenv(name);
    if (!s || !*s) return false;
    try {
        v = std::stod(s);
        return true;
    } catch (...) {
        return false;
    }
}

static bool parse_u32_env(const char *name, uint32_t &v) {
    const char *s = std::getenv(name);
    if (!s || !*s) return false;
    try {
        unsigned long x = std::stoul(s);
        v = static_cast<uint32_t>(x);
        return true;
    } catch (...) {
        return false;
    }
}

static bool parse_string_env(const char *name, std::string &v) {
    const char *s = std::getenv(name);
    if (!s || !*s) return false;
    v = s;
    return true;
}

static Params load_params_from_env() {
    Params p;
    parse_int_env("RUNS", p.runs);
    parse_int_env("NP", p.np);
    parse_int_env("GENERATIONS", p.generations);
    parse_int_env("CONV_RUNS", p.conv_runs);

    parse_int_env("SMABC_LC", p.smabc_lc);
    parse_int_env("SMABC_LS", p.smabc_ls);
    parse_double_env("SMABC_ALPHA1", p.smabc_alpha1);
    parse_double_env("SMABC_ALPHA2", p.smabc_alpha2);
    parse_int_env("SMABC_LIMIT", p.smabc_limit);

    parse_double_env("GA_PC", p.ga_pc);
    parse_double_env("GA_PM", p.ga_pm);

    parse_double_env("PSO_W", p.pso_w);
    parse_double_env("PSO_C1", p.pso_c1);
    parse_double_env("PSO_C2", p.pso_c2);

    parse_u32_env("SEED", p.seed);
    parse_int_env("CACHE_LIMIT", p.cache_limit);

    // Tech-aware cost weights.
    parse_double_env("SMABC_C_AND", p.c_and);
    parse_double_env("SMABC_C_XOR", p.c_xor);
    return p;
}

static Bench parse_pla(const fs::path &path) {
    std::ifstream fin(path);
    if (!fin) {
        throw std::runtime_error("cannot open PLA: " + path.string());
    }

    Bench b;
    b.name = path.stem().string();

    auto trim = [](std::string &s) {
        size_t b = 0;
        while (b < s.size() && std::isspace(static_cast<unsigned char>(s[b]))) b++;
        size_t e = s.size();
        while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) e--;
        s = s.substr(b, e - b);
    };

    std::string line;
    bool first_line = true;
    while (std::getline(fin, line)) {
        if (first_line) {
            first_line = false;
            if (line.size() >= 3 &&
                static_cast<unsigned char>(line[0]) == 0xEF &&
                static_cast<unsigned char>(line[1]) == 0xBB &&
                static_cast<unsigned char>(line[2]) == 0xBF) {
                line.erase(0, 3);
            }
        }

        trim(line);
        if (line.empty()) continue;
        if (line[0] == '.') {
            std::istringstream dss(line);
            std::string directive;
            dss >> directive;
            if (directive == ".i") {
                dss >> b.n;
            }
            continue;
        }

        std::istringstream iss(line);
        std::string in_bits;
        std::string out_bits;
        if (!(iss >> in_bits >> out_bits)) {
            continue;
        }
        if (b.n <= 0 || static_cast<int>(in_bits.size()) != b.n) {
            continue;
        }
        if (out_bits.empty() || out_bits[0] != '1') {
            continue;
        }

        uint32_t m = 0u;
        for (char c : in_bits) {
            m <<= 1u;
            if (c == '1') m |= 1u;
        }
        b.on_set.push_back(m);
    }

    if (b.n <= 0) {
        throw std::runtime_error("missing .i in PLA: " + path.string());
    }
    if (b.n >= 32) {
        throw std::runtime_error("n>=32 unsupported in this implementation: " + path.string());
    }
    b.mask = (b.n == 32) ? 0xFFFFFFFFu : ((1u << b.n) - 1u);
    return b;
}

// ---------------------------------------------------------------------------
// FprmEvaluator
// ---------------------------------------------------------------------------
// Change 3: area() now returns double and uses tech-aware gate weights
// (c_and_, c_xor_) instead of the uniform C_AND=C_XOR=1 used previously.
// Cache stores double values accordingly.
// ---------------------------------------------------------------------------
class FprmEvaluator {
  public:
        explicit FprmEvaluator(const Bench &bench, int cache_limit,
                               double c_and = 1.064, double c_xor = 1.596)
                                : n_(bench.n),
                                    mask_(bench.mask),
                                    on_set_(bench.on_set),
                                    cache_limit_(std::max(0, cache_limit)),
                                    truth_size_(1u << bench.n),
                                    coef_bits_(truth_size_, 0u),
                                    seen_(truth_size_, 0u),
                                    c_and_(c_and),
                                    c_xor_(c_xor) {
                cache_.reserve(static_cast<size_t>(std::min(cache_limit_, 50000)));
                                touched_.reserve(8192);
    }

    double area(uint32_t polarity) {
        polarity &= mask_;
        auto it = cache_.find(polarity);
        if (it != cache_.end()) return it->second;

        if (cache_limit_ > 0 && static_cast<int>(cache_.size()) >= cache_limit_) {
            cache_.clear();
        }

        touched_.clear();
        for (uint32_t m : on_set_) {
            uint32_t y = (m ^ polarity) & mask_;

            // Correct ANF relation:
            // c[a] = XOR_{x subseteq a} f[x]
            // So each on-set minterm y toggles all supersets of y.
            uint32_t free_bits = (mask_ ^ y);
            uint32_t sub = free_bits;
            while (true) {
                uint32_t a = (y | sub);
                if (!seen_[a]) {
                    seen_[a] = 1u;
                    touched_.push_back(a);
                }
                coef_bits_[a] ^= 1u;

                if (sub == 0u) break;
                sub = (sub - 1u) & free_bits;
            }
        }

        int terms = 0;
        int and_gates = 0;
        for (uint32_t c : touched_) {
            if (!coef_bits_[c]) continue;
            ++terms;
            int d = popcount_u32(c);
            if (d > 1) {
                and_gates += (d - 1);
            }
        }

        // Reset workspace marks for next call.
        for (uint32_t c : touched_) {
            coef_bits_[c] = 0u;
            seen_[c] = 0u;
        }

        int xor_gates = (terms > 0) ? (terms - 1) : 0;
        // Tech-aware cost: weighted sum using 45nm library areas.
        double a = c_and_ * static_cast<double>(and_gates)
                 + c_xor_ * static_cast<double>(xor_gates);

        cache_[polarity] = a;
        return a;
    }

  private:
    int n_;
    uint32_t mask_;
    std::vector<uint32_t> on_set_;
    std::unordered_map<uint32_t, double> cache_;
    int cache_limit_;
    uint32_t truth_size_;
    std::vector<uint8_t> coef_bits_;
    std::vector<uint8_t> seen_;
    std::vector<uint32_t> touched_;
    double c_and_;
    double c_xor_;
};

static double area_bruteforce_truth(int n, uint32_t mask,
                                    const std::vector<uint32_t> &on_set,
                                    uint32_t polarity,
                                    double c_and = 1.064,
                                    double c_xor = 1.596) {
    const uint32_t N = (1u << n);
    std::vector<uint8_t> f(N, 0u);
    for (uint32_t m : on_set) {
        f[m & mask] ^= 1u;
    }

    std::vector<uint8_t> g(N, 0u);
    for (uint32_t x = 0u; x < N; ++x) {
        g[x] = f[(x ^ polarity) & mask];
    }

    // Mobius transform from truth table to ANF coefficients over GF(2).
    for (int b = 0; b < n; ++b) {
        uint32_t bit = (1u << b);
        for (uint32_t x = 0u; x < N; ++x) {
            if (x & bit) {
                g[x] ^= g[x ^ bit];
            }
        }
    }

    int terms = 0;
    int and_gates = 0;
    for (uint32_t c = 0u; c < N; ++c) {
        if (!g[c]) continue;
        ++terms;
        int d = popcount_u32(c);
        if (d > 1) and_gates += (d - 1);
    }
    int xor_gates = (terms > 0) ? (terms - 1) : 0;
    return c_and * static_cast<double>(and_gates)
         + c_xor * static_cast<double>(xor_gates);
}

static void verify_method_correctness(uint32_t seed_base,
                                      double c_and, double c_xor) {
    std::mt19937 rng(seed_base ^ 0x9E3779B9u);
    std::uniform_real_distribution<double> ur(0.0, 1.0);

    // Random differential tests: evaluator vs brute-force Mobius transform.
    for (int n = 1; n <= 10; ++n) {
        uint32_t mask = (1u << n) - 1u;
        std::uniform_int_distribution<uint32_t> md(0u, mask);
        for (int t = 0; t < 12; ++t) {
            Bench b;
            b.name = "verify_rand";
            b.n = n;
            b.mask = mask;

            // Build sparse random on-set so validation remains quick.
            int target = std::max(1, n / 2);
            std::unordered_set<uint32_t> used;
            while (static_cast<int>(b.on_set.size()) < target) {
                uint32_t m = md(rng);
                if (used.insert(m).second) b.on_set.push_back(m);
            }

            FprmEvaluator eval(b, 0, c_and, c_xor);
            for (int k = 0; k < 32; ++k) {
                uint32_t p = md(rng);
                double fast_a = eval.area(p);
                double brute_a = area_bruteforce_truth(n, mask, b.on_set, p,
                                                       c_and, c_xor);
                if (std::fabs(fast_a - brute_a) > 1e-9) {
                    std::ostringstream oss;
                    oss << "verification mismatch n=" << n
                        << " polarity=" << p
                        << " fast=" << fast_a
                        << " brute=" << brute_a;
                    throw std::runtime_error(oss.str());
                }
            }
        }
    }

    // Paper Section 3.1 example-style sanity: y = x0x1 XOR x2x3x4
    // has 1 AND(3-1)=2 and-gates and 2-1=1 xor-gate.
    // With c_and=1.064, c_xor=1.596: expected = 2*1.064 + 1*1.596 = 3.724.
    {
        Bench b;
        b.name = "verify_paper_example";
        b.n = 5;
        b.mask = 0x1Fu;

        for (uint32_t x = 0u; x < (1u << 5); ++x) {
            int x0 = (x >> 0) & 1u;
            int x1 = (x >> 1) & 1u;
            int x2 = (x >> 2) & 1u;
            int x3 = (x >> 3) & 1u;
            int x4 = (x >> 4) & 1u;
            int y = (x0 & x1) ^ (x2 & x3 & x4);
            if (y) b.on_set.push_back(x);
        }

        FprmEvaluator eval(b, 0, c_and, c_xor);
        double a = eval.area(0u);
        // and_gates = 1 (x0x1) + 2 (x2x3x4) = 3, xor_gates = 1
        double expected = c_and * 3.0 + c_xor * 1.0;
        if (std::fabs(a - expected) > 1e-9) {
            std::ostringstream oss;
            oss << "paper example check failed: expected " << expected
                << " got " << a;
            throw std::runtime_error(oss.str());
        }
    }
}

static std::unordered_set<std::string> parse_bench_filter() {
    std::unordered_set<std::string> s;
    std::string raw;
    if (!parse_string_env("BENCH_FILTER", raw)) return s;

    std::string cur;
    for (char c : raw) {
        if (c == ',') {
            if (!cur.empty()) s.insert(cur);
            cur.clear();
        } else if (!std::isspace(static_cast<unsigned char>(c))) {
            cur.push_back(c);
        }
    }
    if (!cur.empty()) s.insert(cur);
    return s;
}

static std::vector<uint32_t> compute_anf_coeff_masks(const Bench &b, uint32_t polarity) {
    const uint32_t truth_size = (1u << b.n);
    std::vector<uint8_t> coef_bits(truth_size, 0u);
    std::vector<uint8_t> seen(truth_size, 0u);
    std::vector<uint32_t> touched;
    touched.reserve(8192);

    for (uint32_t m : b.on_set) {
        uint32_t y = (m ^ polarity) & b.mask;
        uint32_t free_bits = (b.mask ^ y);
        uint32_t sub = free_bits;
        while (true) {
            uint32_t a = (y | sub);
            if (!seen[a]) {
                seen[a] = 1u;
                touched.push_back(a);
            }
            coef_bits[a] ^= 1u;

            if (sub == 0u) break;
            sub = (sub - 1u) & free_bits;
        }
    }

    std::vector<uint32_t> coeffs;
    coeffs.reserve(touched.size());
    for (uint32_t c : touched) {
        if (coef_bits[c]) coeffs.push_back(c);
    }
    std::sort(coeffs.begin(), coeffs.end());
    return coeffs;
}

static void emit_literal_for_y(std::ostream &os, int n, int bit_pos, uint32_t polarity) {
    int var_idx = n - 1 - bit_pos;
    if (((polarity >> bit_pos) & 1u) != 0u) {
        os << "~i" << var_idx;
    } else {
        os << "i" << var_idx;
    }
}

static void write_optimized_verilog_from_coeffs(const Bench &b,
                                                uint32_t polarity,
                                                const std::vector<uint32_t> &coeffs,
                                                const fs::path &out_v) {
    std::ofstream f(out_v);
    if (!f) {
        throw std::runtime_error("cannot create verilog: " + out_v.string());
    }

    f << "// Generated by reproduce_paper_full (SMABC method)\n";
    f << "// XOR-and-AND FPRM netlist — map directly without strash\n";
    f << "// to preserve native XOR gate structure during tech-map.\n";
    f << "module " << b.name << "_opt(";
    for (int i = 0; i < b.n; ++i) {
        f << "i" << i << ", ";
    }
    f << "f);\n";

    for (int i = 0; i < b.n; ++i) {
        f << "input i" << i << ";\n";
    }
    f << "output f;\n";

    if (coeffs.empty()) {
        f << "assign f = 1'b0;\n";
        f << "endmodule\n";
        return;
    }

    for (size_t t = 0; t < coeffs.size(); ++t) {
        f << "wire t" << t << ";\n";
    }

    for (size_t t = 0; t < coeffs.size(); ++t) {
        uint32_t c = coeffs[t];
        f << "assign t" << t << " = ";
        if (c == 0u) {
            f << "1'b1";
        } else {
            bool first = true;
            for (int bpos = 0; bpos < b.n; ++bpos) {
                if (((c >> bpos) & 1u) == 0u) continue;
                if (!first) f << " & ";
                emit_literal_for_y(f, b.n, bpos, polarity);
                first = false;
            }
        }
        f << ";\n";
    }

    f << "assign f = ";
    for (size_t t = 0; t < coeffs.size(); ++t) {
        if (t) f << " ^ ";
        f << "t" << t;
    }
    f << ";\n";
    f << "endmodule\n";
}

// ---------------------------------------------------------------------------
// Change 1: XOR faithful mapping chain.
// Writes two companion ABC command script files alongside the Verilog:
//
//   {bench}_xfmap.abc      — delay-optimal map, NO strash (XOR-faithful)
//   {bench}_xfmap_area.abc — area-optimal  map, NO strash (Change 2: 5th group)
//
// Key: omitting "strash" before "map" lets ABC's tech-mapper see the XOR
// gates that are present in the FPRM Verilog (assign f = t0 ^ t1 ^ …).
// The mapper can then match them to native XOR library cells.  Using
// "strash" first would dissolve every XOR into a 3-AIG AND-NOT tree and
// permanently lose the XOR structure.
// ---------------------------------------------------------------------------
static void write_xor_map_abc_scripts(const std::string &bench_name,
                                      const fs::path &verilog_path,
                                      const fs::path &out_dir) {
    const std::string v = verilog_path.string();

    // ---- Script 1: XOR-faithful delay-optimal map (no strash) --------------
    {
        fs::path script = out_dir / (bench_name + "_xfmap.abc");
        std::ofstream f(script);
        if (!f) {
            throw std::runtime_error("cannot create ABC script: " + script.string());
        }
        fs::path blif_out = out_dir / (bench_name + "_xfmap.blif");

        f << "# XOR-faithful tech-map (delay-optimal)\n";
        f << "# Generated by reproduce_paper_full.\n";
        f << "#\n";
        f << "# IMPORTANT: 'strash' is intentionally OMITTED so that the XOR\n";
        f << "# gates in the FPRM Verilog are preserved for native XOR mapping.\n";
        f << "read_verilog " << v << "\n";
        f << "# Do NOT call 'strash' — it would convert XOR to AIG and lose structure.\n";
        f << "map\n";
        f << "print_stats\n";
        f << "write_blif " << blif_out.string() << "\n";
    }

    // ---- Script 2: XOR-faithful area-optimal map (map -a) ------------------
    // Change 2: adds the 5th group (area-priority map) to the comparison set.
    {
        fs::path script = out_dir / (bench_name + "_xfmap_area.abc");
        std::ofstream f(script);
        if (!f) {
            throw std::runtime_error("cannot create ABC script: " + script.string());
        }
        fs::path blif_out = out_dir / (bench_name + "_xfmap_area.blif");

        f << "# XOR-faithful tech-map (area-optimal, map -a)\n";
        f << "# Generated by reproduce_paper_full.\n";
        f << "#\n";
        f << "# 'map -a' selects the area-optimal cover at each node.\n";
        f << "# Strash is again omitted to preserve FPRM XOR structure.\n";
        f << "read_verilog " << v << "\n";
        f << "# Do NOT call 'strash'.\n";
        f << "map -a\n";
        f << "print_stats\n";
        f << "write_blif " << blif_out.string() << "\n";
    }
}

struct AlgoResult {
    double best_area = std::numeric_limits<double>::max();
    uint32_t best_polarity = 0u;
    std::vector<double> best_curve;
};

struct Candidate {
    uint32_t p = 0u;
    double fit = std::numeric_limits<double>::max();
    int trial = 0;
};

static int roulette_pick(const std::vector<double> &w, std::mt19937 &rng) {
    double sum = std::accumulate(w.begin(), w.end(), 0.0);
    if (sum <= 0.0) {
        std::uniform_int_distribution<int> ud(0, static_cast<int>(w.size()) - 1);
        return ud(rng);
    }
    std::uniform_real_distribution<double> ur(0.0, sum);
    double r = ur(rng);
    double acc = 0.0;
    for (int i = 0; i < static_cast<int>(w.size()); ++i) {
        acc += w[i];
        if (r <= acc) return i;
    }
    return static_cast<int>(w.size()) - 1;
}

static uint32_t flip_one_random_bit(uint32_t p, int n, std::mt19937 &rng) {
    std::uniform_int_distribution<int> bd(0, n - 1);
    int b = bd(rng);
    return p ^ (1u << b);
}

static uint32_t flip_k_random_bits(uint32_t p, int n, int k, std::mt19937 &rng) {
    if (k <= 0) return p;
    std::uniform_int_distribution<int> bd(0, n - 1);
    for (int i = 0; i < k; ++i) {
        int b = bd(rng);
        p ^= (1u << b);
    }
    return p;
}

static AlgoResult run_abc(const Bench &bench, FprmEvaluator &eval, const Params &pm, std::mt19937 &rng) {
    const int NP = pm.np;
    const int G = pm.generations;
    const int LIMIT = pm.smabc_limit;

    std::vector<Candidate> pop(NP);
    AlgoResult r;
    r.best_curve.resize(G);

    for (int i = 0; i < NP; ++i) {
        pop[i].p = rand_polarity(rng, bench.mask);
        pop[i].fit = eval.area(pop[i].p);
        pop[i].trial = 0;
        if (pop[i].fit < r.best_area) {
            r.best_area = pop[i].fit;
            r.best_polarity = pop[i].p;
        }
    }

    for (int g = 0; g < G; ++g) {
        // Employed bees.
        for (int i = 0; i < NP; ++i) {
            uint32_t cand = flip_one_random_bit(pop[i].p, bench.n, rng) & bench.mask;
            double f = eval.area(cand);
            if (f < pop[i].fit) {
                pop[i].p = cand;
                pop[i].fit = f;
                pop[i].trial = 0;
            } else {
                pop[i].trial++;
            }
        }

        // Followers.
        std::vector<double> w(NP, 0.0);
        for (int i = 0; i < NP; ++i) {
            w[i] = 1.0 / (1.0 + pop[i].fit);
        }
        for (int t = 0; t < NP; ++t) {
            int i = roulette_pick(w, rng);
            uint32_t cand = flip_one_random_bit(pop[i].p, bench.n, rng) & bench.mask;
            double f = eval.area(cand);
            if (f < pop[i].fit) {
                pop[i].p = cand;
                pop[i].fit = f;
                pop[i].trial = 0;
            } else {
                pop[i].trial++;
            }
        }

        // Scouts.
        for (int i = 0; i < NP; ++i) {
            if (pop[i].trial >= LIMIT) {
                pop[i].p = rand_polarity(rng, bench.mask);
                pop[i].fit = eval.area(pop[i].p);
                pop[i].trial = 0;
            }
        }

        for (int i = 0; i < NP; ++i) {
            if (pop[i].fit < r.best_area) {
                r.best_area = pop[i].fit;
                r.best_polarity = pop[i].p;
            }
        }
        r.best_curve[g] = r.best_area;
    }

    return r;
}

static AlgoResult run_smabc(const Bench &bench, FprmEvaluator &eval, const Params &pm, std::mt19937 &rng) {
    const int NP = pm.np;
    const int G = pm.generations;

    std::vector<Candidate> pop(NP);
    AlgoResult r;
    r.best_curve.resize(G);

    for (int i = 0; i < NP; ++i) {
        pop[i].p = rand_polarity(rng, bench.mask);
        pop[i].fit = eval.area(pop[i].p);
        pop[i].trial = 0;
        if (pop[i].fit < r.best_area) {
            r.best_area = pop[i].fit;
            r.best_polarity = pop[i].p;
        }
    }

    for (int g = 0; g < G; ++g) {
        // Leader bee search with chemotaxis-like greedy one-bit neighborhood walk.
        for (int i = 0; i < NP; ++i) {
            uint32_t cur_p = pop[i].p;
            double cur_f = pop[i].fit;
            bool improved_any = false;

            for (int step = 0; step < pm.smabc_lc; ++step) {
                double best_f = cur_f;
                uint32_t best_p = cur_p;

                for (int b = 0; b < bench.n; ++b) {
                    uint32_t cand = (cur_p ^ (1u << b)) & bench.mask;
                    double f = eval.area(cand);
                    if (f < best_f) {
                        best_f = f;
                        best_p = cand;
                    }
                }

                if (best_f < cur_f) {
                    cur_f = best_f;
                    cur_p = best_p;
                    improved_any = true;
                } else {
                    break;
                }
            }

            if (improved_any) {
                pop[i].p = cur_p;
                pop[i].fit = cur_f;
                pop[i].trial = 0;
            } else {
                pop[i].trial++;
            }
        }

        // Adaptive follower choose.
        double beta = pm.smabc_alpha1 + (pm.smabc_alpha2 * static_cast<double>(g));
        std::vector<double> w(NP, 0.0);
        for (int i = 0; i < NP; ++i) {
            double base = 1.0 / (1.0 + pop[i].fit);
            w[i] = std::pow(base, std::max(0.1, beta));
        }

        std::uniform_int_distribution<int> flips_dist(1, std::max(1, pm.smabc_ls));
        for (int t = 0; t < NP; ++t) {
            int i = roulette_pick(w, rng);
            int flips = flips_dist(rng);
            uint32_t cand = flip_k_random_bits(pop[i].p, bench.n, flips, rng) & bench.mask;
            double f = eval.area(cand);
            if (f < pop[i].fit) {
                pop[i].p = cand;
                pop[i].fit = f;
                pop[i].trial = 0;
            } else {
                pop[i].trial++;
            }
        }

        // Scout with adaptive perturbation.
        for (int i = 0; i < NP; ++i) {
            if (pop[i].trial >= pm.smabc_limit) {
                int flips = std::max(1, pm.smabc_ls);
                uint32_t base = rand_polarity(rng, bench.mask);
                uint32_t cand = flip_k_random_bits(base, bench.n, flips, rng) & bench.mask;
                pop[i].p = cand;
                pop[i].fit = eval.area(cand);
                pop[i].trial = 0;
            }
        }

        // Elitism: keep global best individual in population.
        int worst_i = 0;
        for (int i = 1; i < NP; ++i) {
            if (pop[i].fit > pop[worst_i].fit) worst_i = i;
        }
        pop[worst_i].p = r.best_polarity;
        pop[worst_i].fit = r.best_area;
        pop[worst_i].trial = 0;

        for (int i = 0; i < NP; ++i) {
            if (pop[i].fit < r.best_area) {
                r.best_area = pop[i].fit;
                r.best_polarity = pop[i].p;
            }
        }
        r.best_curve[g] = r.best_area;
    }

    return r;
}

static int tournament_pick(const std::vector<Candidate> &pop, std::mt19937 &rng, int k = 3) {
    std::uniform_int_distribution<int> ud(0, static_cast<int>(pop.size()) - 1);
    int best = ud(rng);
    for (int i = 1; i < k; ++i) {
        int c = ud(rng);
        if (pop[c].fit < pop[best].fit) best = c;
    }
    return best;
}

static AlgoResult run_ga(const Bench &bench, FprmEvaluator &eval, const Params &pm, std::mt19937 &rng) {
    const int NP = pm.np;
    const int G = pm.generations;

    std::vector<Candidate> pop(NP);
    AlgoResult r;
    r.best_curve.resize(G);

    std::uniform_real_distribution<double> ur(0.0, 1.0);

    for (int i = 0; i < NP; ++i) {
        pop[i].p = rand_polarity(rng, bench.mask);
        pop[i].fit = eval.area(pop[i].p);
        if (pop[i].fit < r.best_area) {
            r.best_area = pop[i].fit;
            r.best_polarity = pop[i].p;
        }
    }

    for (int g = 0; g < G; ++g) {
        std::vector<Candidate> next;
        next.reserve(NP);

        // Elitism.
        int elite = 0;
        for (int i = 1; i < NP; ++i) {
            if (pop[i].fit < pop[elite].fit) elite = i;
        }
        next.push_back(pop[elite]);

        while (static_cast<int>(next.size()) < NP) {
            int i1 = tournament_pick(pop, rng, 3);
            int i2 = tournament_pick(pop, rng, 3);
            uint32_t p1 = pop[i1].p;
            uint32_t p2 = pop[i2].p;
            uint32_t c1 = p1;
            uint32_t c2 = p2;

            if (bench.n > 1 && ur(rng) < pm.ga_pc) {
                std::uniform_int_distribution<int> cp_dist(1, bench.n - 1);
                int cp = cp_dist(rng);
                uint32_t low = (1u << cp) - 1u;
                uint32_t high = bench.mask ^ low;
                c1 = (p1 & low) | (p2 & high);
                c2 = (p2 & low) | (p1 & high);
            }

            for (int b = 0; b < bench.n; ++b) {
                if (ur(rng) < pm.ga_pm) c1 ^= (1u << b);
                if (ur(rng) < pm.ga_pm) c2 ^= (1u << b);
            }
            c1 &= bench.mask;
            c2 &= bench.mask;

            Candidate n1;
            n1.p = c1;
            n1.fit = eval.area(c1);
            next.push_back(n1);

            if (static_cast<int>(next.size()) < NP) {
                Candidate n2;
                n2.p = c2;
                n2.fit = eval.area(c2);
                next.push_back(n2);
            }
        }

        pop.swap(next);

        for (const auto &c : pop) {
            if (c.fit < r.best_area) {
                r.best_area = c.fit;
                r.best_polarity = c.p;
            }
        }
        r.best_curve[g] = r.best_area;
    }

    return r;
}

struct Particle {
    uint32_t p = 0u;
    double fit = std::numeric_limits<double>::max();
    uint32_t pbest_p = 0u;
    double pbest_fit = std::numeric_limits<double>::max();
    std::vector<double> v;
};

static AlgoResult run_pso(const Bench &bench, FprmEvaluator &eval, const Params &pm, std::mt19937 &rng) {
    const int NP = pm.np;
    const int G = pm.generations;

    std::vector<Particle> swarm(NP);
    AlgoResult r;
    r.best_curve.resize(G);

    std::uniform_real_distribution<double> ur(0.0, 1.0);

    for (int i = 0; i < NP; ++i) {
        swarm[i].p = rand_polarity(rng, bench.mask);
        swarm[i].fit = eval.area(swarm[i].p);
        swarm[i].pbest_p = swarm[i].p;
        swarm[i].pbest_fit = swarm[i].fit;
        swarm[i].v.assign(bench.n, 0.0);

        if (swarm[i].fit < r.best_area) {
            r.best_area = swarm[i].fit;
            r.best_polarity = swarm[i].p;
        }
    }

    for (int g = 0; g < G; ++g) {
        for (int i = 0; i < NP; ++i) {
            uint32_t new_p = swarm[i].p;
            for (int b = 0; b < bench.n; ++b) {
                int xb = (swarm[i].p >> b) & 1u;
                int pb = (swarm[i].pbest_p >> b) & 1u;
                int gb = (r.best_polarity >> b) & 1u;

                double r1 = ur(rng);
                double r2 = ur(rng);
                double v = pm.pso_w * swarm[i].v[b]
                         + pm.pso_c1 * r1 * (static_cast<double>(pb - xb))
                         + pm.pso_c2 * r2 * (static_cast<double>(gb - xb));
                v = std::max(-6.0, std::min(6.0, v));
                swarm[i].v[b] = v;

                double s = 1.0 / (1.0 + std::exp(-v));
                if (ur(rng) < s) {
                    new_p |= (1u << b);
                } else {
                    new_p &= ~(1u << b);
                }
            }

            new_p &= bench.mask;
            swarm[i].p = new_p;
            swarm[i].fit = eval.area(new_p);

            if (swarm[i].fit < swarm[i].pbest_fit) {
                swarm[i].pbest_fit = swarm[i].fit;
                swarm[i].pbest_p = swarm[i].p;
            }
            if (swarm[i].fit < r.best_area) {
                r.best_area = swarm[i].fit;
                r.best_polarity = swarm[i].p;
            }
        }

        r.best_curve[g] = r.best_area;
    }

    return r;
}

struct BenchStats {
    std::string name;
    int n = 0;
    double a_pso = 0.0;
    double a_ga = 0.0;
    double a_abc = 0.0;
    double a_smabc = 0.0;
    double asave1 = 0.0;
    double asave2 = 0.0;
    double asave3 = 0.0;
};

static double mean_d(const std::vector<double> &v) {
    if (v.empty()) return 0.0;
    double s = 0.0;
    for (double x : v) s += x;
    return s / static_cast<double>(v.size());
}

static uint32_t stable_seed(uint32_t base, const std::string &name, int run_id, int algo_id) {
    uint32_t h = 2166136261u;
    for (unsigned char c : name) {
        h ^= c;
        h *= 16777619u;
    }
    h ^= static_cast<uint32_t>(run_id * 131 + algo_id * 911);
    h *= 2654435761u;
    return base ^ h;
}

int main() {
    try {
        std::cout.setf(std::ios::unitbuf);
        Params pm = load_params_from_env();
        auto bench_filter = parse_bench_filter();

        std::string export_v_dir;
        parse_string_env("EXPORT_OPT_VERILOG_DIR", export_v_dir);
        std::string export_algo = "SMABC";
        parse_string_env("EXPORT_OPT_ALGO", export_algo);
        for (char &c : export_algo) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        bool export_v = !export_v_dir.empty();
        if (export_v) {
            fs::create_directories(fs::path(export_v_dir));
            std::cout << "[export] verilog dir: " << export_v_dir << " (algo=" << export_algo << ")\n";
        }

        std::cout << "[params] c_and=" << pm.c_and << " c_xor=" << pm.c_xor
                  << " (45nm NangateOpenCellLibrary: AND2_X1=1.064 XOR2_X1=1.596)\n";

        int verify_flag = 1;
        parse_int_env("VERIFY_METHOD", verify_flag);
        if (verify_flag != 0) {
            std::cout << "[verify] checking evaluator/method consistency...\n";
            verify_method_correctness(pm.seed, pm.c_and, pm.c_xor);
            std::cout << "[verify] method checks passed.\n";
        }

        const fs::path root = fs::current_path();
        const fs::path bench_dir = root / "benchmarks";
        const fs::path out_dir = root / "paper_reproduce_out";
        fs::create_directories(out_dir);

        std::vector<fs::path> pla_files;
        for (const auto &e : fs::directory_iterator(bench_dir)) {
            if (e.is_regular_file() && e.path().extension() == ".pla") {
                pla_files.push_back(e.path());
            }
        }
        std::sort(pla_files.begin(), pla_files.end());

        if (pla_files.empty()) {
            std::cerr << "[error] no PLA files found under " << bench_dir.string() << "\n";
            return 1;
        }

        std::ofstream table2_csv(out_dir / "table2_reproduce.csv");
        std::ofstream runs_csv(out_dir / "raw_runs.csv");
        std::ofstream conv_csv(out_dir / "convergence_avg10.csv");
        std::ofstream summary_txt(out_dir / "summary.txt");

        table2_csv.setf(std::ios::unitbuf);
        runs_csv.setf(std::ios::unitbuf);
        conv_csv.setf(std::ios::unitbuf);
        summary_txt.setf(std::ios::unitbuf);

        table2_csv << "bench,n,A_PSO,A_GA,A_ABC,A_SMABC,Asave1_pct,Asave2_pct,Asave3_pct\n";
        runs_csv << "bench,run,A_PSO,A_GA,A_ABC,A_SMABC,bestP_PSO,bestP_GA,bestP_ABC,bestP_SMABC\n";
        conv_csv << "bench,algo,generation,avg_best_area\n";

        std::vector<BenchStats> all_stats;
        int selected = 0;

        for (const auto &pf : pla_files) {
            Bench b = parse_pla(pf);
            if (!bench_filter.empty() && bench_filter.find(b.name) == bench_filter.end()) {
                continue;
            }
            selected++;
            FprmEvaluator eval(b, pm.cache_limit, pm.c_and, pm.c_xor);

            std::vector<double> pso_runs, ga_runs, abc_runs, smabc_runs;
            pso_runs.reserve(pm.runs);
            ga_runs.reserve(pm.runs);
            abc_runs.reserve(pm.runs);
            smabc_runs.reserve(pm.runs);

            std::vector<double> conv_pso(pm.generations, 0.0);
            std::vector<double> conv_ga(pm.generations, 0.0);
            std::vector<double> conv_abc(pm.generations, 0.0);
            std::vector<double> conv_smabc(pm.generations, 0.0);

            double best_a_pso = std::numeric_limits<double>::max();
            double best_a_ga  = std::numeric_limits<double>::max();
            double best_a_abc = std::numeric_limits<double>::max();
            double best_a_smabc = std::numeric_limits<double>::max();
            uint32_t best_p_pso = 0u;
            uint32_t best_p_ga = 0u;
            uint32_t best_p_abc = 0u;
            uint32_t best_p_smabc = 0u;

            std::cout << "[bench] " << b.name << " n=" << b.n << " on_set=" << b.on_set.size() << "\n";

            for (int run = 1; run <= pm.runs; ++run) {
                std::mt19937 rng_pso(stable_seed(pm.seed, b.name, run, 1));
                std::mt19937 rng_ga(stable_seed(pm.seed, b.name, run, 2));
                std::mt19937 rng_abc(stable_seed(pm.seed, b.name, run, 3));
                std::mt19937 rng_smabc(stable_seed(pm.seed, b.name, run, 4));

                AlgoResult pso = run_pso(b, eval, pm, rng_pso);
                AlgoResult ga = run_ga(b, eval, pm, rng_ga);
                AlgoResult abc = run_abc(b, eval, pm, rng_abc);
                AlgoResult smabc = run_smabc(b, eval, pm, rng_smabc);

                if (pso.best_area < best_a_pso) {
                    best_a_pso = pso.best_area;
                    best_p_pso = pso.best_polarity;
                }
                if (ga.best_area < best_a_ga) {
                    best_a_ga = ga.best_area;
                    best_p_ga = ga.best_polarity;
                }
                if (abc.best_area < best_a_abc) {
                    best_a_abc = abc.best_area;
                    best_p_abc = abc.best_polarity;
                }
                if (smabc.best_area < best_a_smabc) {
                    best_a_smabc = smabc.best_area;
                    best_p_smabc = smabc.best_polarity;
                }

                pso_runs.push_back(pso.best_area);
                ga_runs.push_back(ga.best_area);
                abc_runs.push_back(abc.best_area);
                smabc_runs.push_back(smabc.best_area);

                if (run <= pm.conv_runs) {
                    for (int g = 0; g < pm.generations; ++g) {
                        conv_pso[g] += pso.best_curve[g];
                        conv_ga[g] += ga.best_curve[g];
                        conv_abc[g] += abc.best_curve[g];
                        conv_smabc[g] += smabc.best_curve[g];
                    }
                }

                runs_csv << b.name << "," << run << ","
                         << std::fixed << std::setprecision(4)
                         << pso.best_area << "," << ga.best_area << ","
                         << abc.best_area << "," << smabc.best_area << ","
                         << pso.best_polarity << "," << ga.best_polarity << ","
                         << abc.best_polarity << "," << smabc.best_polarity << "\n";

                std::cout << "  run " << std::setw(2) << run
                          << " | PSO=" << std::fixed << std::setprecision(3) << pso.best_area
                          << " GA=" << ga.best_area
                          << " ABC=" << abc.best_area
                          << " SMABC=" << smabc.best_area << "\n";
            }

            // ----------------------------------------------------------------
            // Export: Verilog + XOR-faithful ABC map scripts
            // (Changes 1 & 2)
            // ----------------------------------------------------------------
            if (export_v) {
                uint32_t chosen_p = best_p_smabc;
                double chosen_a = best_a_smabc;
                if (export_algo == "ABC") {
                    chosen_p = best_p_abc;
                    chosen_a = best_a_abc;
                } else if (export_algo == "GA") {
                    chosen_p = best_p_ga;
                    chosen_a = best_a_ga;
                } else if (export_algo == "PSO") {
                    chosen_p = best_p_pso;
                    chosen_a = best_a_pso;
                }

                auto coeffs = compute_anf_coeff_masks(b, chosen_p);
                int and_gates_v = 0, xor_gates_v = 0;
                for (uint32_t c : coeffs) {
                    int d = popcount_u32(c);
                    if (d > 1) and_gates_v += (d - 1);
                }
                if (!coeffs.empty()) xor_gates_v = static_cast<int>(coeffs.size()) - 1;
                double recomputed_a = pm.c_and * static_cast<double>(and_gates_v)
                                    + pm.c_xor * static_cast<double>(xor_gates_v);

                if (std::fabs(recomputed_a - chosen_a) > 1e-6) {
                    std::ostringstream oss;
                    oss << "export area mismatch bench=" << b.name
                        << " chosen_a=" << chosen_a
                        << " recomputed_a=" << recomputed_a;
                    throw std::runtime_error(oss.str());
                }

                fs::path out_v = fs::path(export_v_dir) / (b.name + "_opt.v");
                write_optimized_verilog_from_coeffs(b, chosen_p, coeffs, out_v);

                // Change 1 + Change 2: emit XOR-faithful ABC map scripts.
                write_xor_map_abc_scripts(b.name, out_v, fs::path(export_v_dir));
                std::cout << "  [export] " << b.name << "_opt.v + _xfmap.abc + _xfmap_area.abc\n";
            }

            double A_PSO   = mean_d(pso_runs);
            double A_GA    = mean_d(ga_runs);
            double A_ABC   = mean_d(abc_runs);
            double A_SMABC = mean_d(smabc_runs);

            auto safe_save = [](double A_ref, double A_smabc) {
                if (A_ref <= 0.0) return 0.0;
                return (A_ref - A_smabc) / A_ref * 100.0;
            };

            double Asave1 = safe_save(A_PSO, A_SMABC);
            double Asave2 = safe_save(A_GA, A_SMABC);
            double Asave3 = safe_save(A_ABC, A_SMABC);

            BenchStats bs;
            bs.name = b.name;
            bs.n = b.n;
            bs.a_pso = A_PSO;
            bs.a_ga = A_GA;
            bs.a_abc = A_ABC;
            bs.a_smabc = A_SMABC;
            bs.asave1 = Asave1;
            bs.asave2 = Asave2;
            bs.asave3 = Asave3;
            all_stats.push_back(bs);

            table2_csv << b.name << "," << b.n << ","
                       << std::fixed << std::setprecision(4)
                       << A_PSO << "," << A_GA << "," << A_ABC << "," << A_SMABC << ","
                       << std::setprecision(3)
                       << Asave1 << "," << Asave2 << "," << Asave3 << "\n";

            double denom = static_cast<double>(std::max(1, std::min(pm.conv_runs, pm.runs)));
            for (int g = 0; g < pm.generations; ++g) {
                conv_csv << b.name << ",PSO,"   << (g + 1) << "," << (conv_pso[g]   / denom) << "\n";
                conv_csv << b.name << ",GA,"    << (g + 1) << "," << (conv_ga[g]    / denom) << "\n";
                conv_csv << b.name << ",ABC,"   << (g + 1) << "," << (conv_abc[g]   / denom) << "\n";
                conv_csv << b.name << ",SMABC," << (g + 1) << "," << (conv_smabc[g] / denom) << "\n";
            }
        }

        if (selected == 0) {
            std::cerr << "[error] no benchmark selected; check BENCH_FILTER.\n";
            return 1;
        }

        // Summary statistics.
        double sum1 = 0.0, sum2 = 0.0, sum3 = 0.0;
        double max1 = -1e9, max2 = -1e9, max3 = -1e9;
        std::string max1_b, max2_b, max3_b;

        for (const auto &s : all_stats) {
            sum1 += s.asave1;
            sum2 += s.asave2;
            sum3 += s.asave3;
            if (s.asave1 > max1) { max1 = s.asave1; max1_b = s.name; }
            if (s.asave2 > max2) { max2 = s.asave2; max2_b = s.name; }
            if (s.asave3 > max3) { max3 = s.asave3; max3_b = s.name; }
        }

        const double nbench = static_cast<double>(std::max<size_t>(1, all_stats.size()));
        double avg1 = sum1 / nbench;
        double avg2 = sum2 / nbench;
        double avg3 = sum3 / nbench;

        summary_txt << "Paper-style reproduction summary\n";
        summary_txt << "RUNS=" << pm.runs << " NP=" << pm.np << " G=" << pm.generations << "\n";
        summary_txt << "c_and=" << pm.c_and << " c_xor=" << pm.c_xor
                    << " (45nm NangateOpenCellLibrary)\n\n";
        summary_txt << std::fixed << std::setprecision(3);
        summary_txt << "Asave1 (vs PSO): avg=" << avg1 << "% max=" << max1 << "% @" << max1_b << "\n";
        summary_txt << "Asave2 (vs GA ): avg=" << avg2 << "% max=" << max2 << "% @" << max2_b << "\n";
        summary_txt << "Asave3 (vs ABC): avg=" << avg3 << "% max=" << max3 << "% @" << max3_b << "\n";

        std::cout << "\n[done] outputs in: " << out_dir.string() << "\n";
        std::cout << "  - table2_reproduce.csv\n";
        std::cout << "  - raw_runs.csv\n";
        std::cout << "  - convergence_avg10.csv\n";
        std::cout << "  - summary.txt\n";
        if (export_v) {
            std::cout << "  - *_opt.v  (XOR-and-AND FPRM netlists)\n";
            std::cout << "  - *_xfmap.abc      (XOR-faithful delay map, no strash)\n";
            std::cout << "  - *_xfmap_area.abc (XOR-faithful area  map, no strash, map -a)\n";
        }

    } catch (const std::exception &e) {
        std::cerr << "[fatal] " << e.what() << "\n";
        return 1;
    }

    return 0;
}
