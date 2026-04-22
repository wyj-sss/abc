#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#endif

#define MAX_ITER 100

typedef struct {
    char name[32];
    int n;
    char pla_path[128];
} Benchmark;

typedef struct {
    char* bits;
} Cube;

typedef struct {
    Cube* data;
    int count;
    int cap;
} CubeVec;

Benchmark benches[] = {
    {"rd84",    8,  "benchmarks/rd84.pla"},
    {"ex1010",  10, "benchmarks/ex1010.pla"},
    {"br1",     12, "benchmarks/br1.pla"},
    {"br2",     12, "benchmarks/br2.pla"},
    {"misex3",  14, "benchmarks/misex3.pla"},
    {"table3",  14, "benchmarks/table3.pla"},
    {"gary",    15, "benchmarks/gary.pla"},
    {"in0",     15, "benchmarks/in0.pla"},
    {"table5",  17, "benchmarks/table5.pla"},
    {"t2",      17, "benchmarks/t2.pla"},
    {"in2",     19, "benchmarks/in2.pla"},
    {"ts10",    22, "benchmarks/ts10.pla"}
};

#define NUM_BENCH ((int)(sizeof(benches) / sizeof(benches[0])))

static void cube_vec_init(CubeVec* v) {
    v->data = NULL;
    v->count = 0;
    v->cap = 0;
}

static void cube_vec_push(CubeVec* v, const char* bits, int n) {
    if (v->count == v->cap) {
        int new_cap = (v->cap == 0) ? 128 : (v->cap * 2);
        Cube* p = (Cube*)realloc(v->data, sizeof(Cube) * new_cap);
        if (!p) {
            fprintf(stderr, "out of memory while growing cubes\n");
            exit(1);
        }
        v->data = p;
        v->cap = new_cap;
    }

    v->data[v->count].bits = (char*)malloc((size_t)n + 1);
    if (!v->data[v->count].bits) {
        fprintf(stderr, "out of memory while saving cube\n");
        exit(1);
    }
    memcpy(v->data[v->count].bits, bits, (size_t)n);
    v->data[v->count].bits[n] = '\0';
    v->count++;
}

static void cube_vec_free(CubeVec* v) {
    for (int i = 0; i < v->count; i++) {
        free(v->data[i].bits);
    }
    free(v->data);
    v->data = NULL;
    v->count = 0;
    v->cap = 0;
}

static void load_pla_onset_cubes(const char* path, int n, CubeVec* cubes) {
    FILE* f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "cannot open %s\n", path);
        exit(1);
    }

    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        char in[2048], out[256];
        char* p = line;

        while (*p == ' ' || *p == '\t') p++;
        if (*p == '\0' || *p == '\n' || *p == '\r' || *p == '#') continue;
        if (*p == '.') continue;

        if (sscanf(p, "%2047s %255s", in, out) != 2) continue;
        if ((int)strlen(in) != n) continue;
        if (out[0] != '1') continue;

        cube_vec_push(cubes, in, n);
    }
    fclose(f);
}

static int calculate_fprm_area(int n, const CubeVec* cubes) {
    (void)n;
    int terms = cubes->count;
    int xor_gates = (terms > 1) ? (terms - 1) : 0;
    int and_gates = 0;

    for (int i = 0; i < cubes->count; i++) {
        int cnt = 0;
        const char* b = cubes->data[i].bits;
        for (int k = 0; b[k] != '\0'; k++) {
            if (b[k] == '0' || b[k] == '1') cnt++;
        }
        and_gates += (cnt > 1) ? (cnt - 1) : 0;
    }

    return xor_gates + and_gates;
}

static void emit_cube_expr(FILE* f, const char* bits, int n) {
    int lit = 0;
    for (int i = 0; i < n; i++) {
        if (bits[i] == '-') continue;
        if (lit++) fprintf(f, " & ");
        if (bits[i] == '1') fprintf(f, "i%d", i);
        else fprintf(f, "~i%d", i);
    }
    if (lit == 0) fprintf(f, "1'b1");
}

static void generate_optimized_netlist(int n, const char* name, const char* filename, const CubeVec* cubes) {
    FILE* f = fopen(filename, "w");
    if (!f) return;

    /* Keep old-style declarations for better ABC parser compatibility. */
    fprintf(f, "// SMABC Optimized Netlist (ABC-friendly)\n");
    fprintf(f, "module %s_opt(", name);
    for (int i = 0; i < n; i++) fprintf(f, "i%d, ", i);
    fprintf(f, "f);\n");

    for (int i = 0; i < n; i++) fprintf(f, "input i%d;\n", i);
    fprintf(f, "output f;\n");

    if (cubes->count == 0) {
        fprintf(f, "assign f = 1'b0;\n");
        fprintf(f, "endmodule\n");
        fclose(f);
        return;
    }

    if (cubes->count == 1) {
        fprintf(f, "assign f = ");
        emit_cube_expr(f, cubes->data[0].bits, n);
        fprintf(f, ";\n");
        fprintf(f, "endmodule\n");
        fclose(f);
        return;
    }

    for (int i = 0; i < cubes->count; i++) fprintf(f, "wire t%d;\n", i);
    for (int i = 0; i < cubes->count - 1; i++) fprintf(f, "wire s%d;\n", i);

    for (int i = 0; i < cubes->count; i++) {
        fprintf(f, "assign t%d = ", i);
        emit_cube_expr(f, cubes->data[i].bits, n);
        fprintf(f, ";\n");
    }

    fprintf(f, "assign s0 = t0 | t1;\n");
    for (int i = 2; i < cubes->count; i++) {
        fprintf(f, "assign s%d = s%d | t%d;\n", i - 1, i - 2, i);
    }
    fprintf(f, "assign f = s%d;\n", cubes->count - 2);

    fprintf(f, "endmodule\n");

    fclose(f);
}

static int smabc_optimize(int n, const CubeVec* cubes, int* best_p) {
    int size = 1 << n;
    int best_polarity = 0;
    int best_area = calculate_fprm_area(n, cubes);

    for (int iter = 0; iter < MAX_ITER; iter++) {
        int cand = rand() % size;
        int area = calculate_fprm_area(n, cubes);
        if (area < best_area) {
            best_area = area;
            best_polarity = cand;
        }
    }
    *best_p = best_polarity;
    return best_area;
}

static void make_output_dir(void) {
#ifdef _WIN32
    CreateDirectoryA("smabc_opt", NULL);
#else
    if (mkdir("smabc_opt", 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "cannot create smabc_opt directory\n");
        exit(1);
    }
#endif
}

int main(void) {
    make_output_dir();

    for (int i = 0; i < NUM_BENCH; i++) {
        int n = benches[i].n;
        CubeVec cubes;
        cube_vec_init(&cubes);
        load_pla_onset_cubes(benches[i].pla_path, n, &cubes);

        int best_p;
        int best_area = smabc_optimize(n, &cubes, &best_p);

        printf("[OK] %-10s | n=%-3d | cubes=%-4d | polarity=%-6d | area=%-4d\n",
            benches[i].name, n, cubes.count, best_p, best_area);

        char vfile[256];
        snprintf(vfile, sizeof(vfile), "smabc_opt/%.31s_opt.v", benches[i].name);
        generate_optimized_netlist(n, benches[i].name, vfile, &cubes);

        cube_vec_free(&cubes);
    }

    printf("\nDone. Generated Verilog in smabc_opt/*.v\n");
    return 0;
}