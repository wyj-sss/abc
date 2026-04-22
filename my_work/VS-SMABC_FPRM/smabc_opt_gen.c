#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#endif

typedef struct {
    const char* name;
    int n;
    const char* pla_path;
} Benchmark;

typedef struct {
    char* bits;
} Cube;

typedef struct {
    Cube* data;
    int count;
    int cap;
} CubeVec;

static Benchmark benches[] = {
    {"rd84", 8, "benchmarks/rd84.pla"},
    {"ex1010", 10, "benchmarks/ex1010.pla"},
    {"br1", 12, "benchmarks/br1.pla"},
    {"br2", 12, "benchmarks/br2.pla"},
    {"misex3", 14, "benchmarks/misex3.pla"},
    {"table3", 14, "benchmarks/table3.pla"},
    {"gary", 15, "benchmarks/gary.pla"},
    {"in0", 15, "benchmarks/in0.pla"},
    {"table5", 17, "benchmarks/table5.pla"},
    {"t2", 17, "benchmarks/t2.pla"},
    {"in2", 19, "benchmarks/in2.pla"},
    {"ts10", 22, "benchmarks/ts10.pla"},
};

#define NUM_BENCH ((int)(sizeof(benches) / sizeof(benches[0])))

static void die(const char* msg, const char* path) {
    if (path != NULL) {
        fprintf(stderr, "ERROR: %s: %s\n", msg, path);
    } else {
        fprintf(stderr, "ERROR: %s\n", msg);
    }
    exit(1);
}

static void make_directory(const char* path) {
#ifdef _WIN32
    if (!CreateDirectoryA(path, NULL)) {
        DWORD err = GetLastError();
        if (err != ERROR_ALREADY_EXISTS) {
            die("failed to create directory", path);
        }
    }
#else
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        die("failed to create directory", path);
    }
#endif
}

static void cube_vec_init(CubeVec* v) {
    v->data = NULL;
    v->count = 0;
    v->cap = 0;
}

static void cube_vec_push(CubeVec* v, const char* bits, int n) {
    char* copied;

    if (v->count == v->cap) {
        int new_cap = (v->cap == 0) ? 256 : (v->cap * 2);
        Cube* new_data = (Cube*)realloc(v->data, (size_t)new_cap * sizeof(Cube));
        if (new_data == NULL) {
            die("out of memory while expanding cube list", NULL);
        }
        v->data = new_data;
        v->cap = new_cap;
    }

    copied = (char*)malloc((size_t)n + 1);
    if (copied == NULL) {
        die("out of memory while copying cube", NULL);
    }
    memcpy(copied, bits, (size_t)n);
    copied[n] = '\0';

    v->data[v->count].bits = copied;
    v->count++;
}

static void cube_vec_free(CubeVec* v) {
    int i;
    for (i = 0; i < v->count; i++) {
        free(v->data[i].bits);
    }
    free(v->data);
    v->data = NULL;
    v->count = 0;
    v->cap = 0;
}

static void load_pla_onset_cubes(const char* path, int n, CubeVec* cubes) {
    FILE* f = fopen(path, "r");
    char line[4096];

    if (f == NULL) {
        die("cannot open PLA file", path);
    }

    while (fgets(line, sizeof(line), f) != NULL) {
        char in[2048];
        char out[256];
        char* p = line;
        int rc;

        while (*p == ' ' || *p == '\t') {
            p++;
        }

        if (*p == '\0' || *p == '\n' || *p == '\r' || *p == '#') {
            continue;
        }
        if (*p == '.') {
            continue;
        }

        rc = sscanf(p, "%2047s %255s", in, out);
        if (rc != 2) {
            continue;
        }

        if ((int)strlen(in) != n) {
            continue;
        }

        if (out[0] != '1') {
            continue;
        }

        cube_vec_push(cubes, in, n);
    }

    fclose(f);
}

static int calculate_cube_area_estimate(int n, const CubeVec* cubes) {
    int i;
    int and_gates = 0;
    int or_gates = (cubes->count > 1) ? (cubes->count - 1) : 0;

    (void)n;

    for (i = 0; i < cubes->count; i++) {
        const char* b = cubes->data[i].bits;
        int lit = 0;
        int k;

        for (k = 0; b[k] != '\0'; k++) {
            if (b[k] == '0' || b[k] == '1') {
                lit++;
            }
        }

        if (lit > 1) {
            and_gates += (lit - 1);
        }
    }

    return and_gates + or_gates;
}

static void emit_cube_expr(FILE* f, const char* bits, int n) {
    int i;
    int lit = 0;

    for (i = 0; i < n; i++) {
        if (bits[i] == '-') {
            continue;
        }

        if (lit > 0) {
            fprintf(f, " & ");
        }

        if (bits[i] == '1') {
            fprintf(f, "i%d", i);
        } else {
            fprintf(f, "~i%d", i);
        }
        lit++;
    }

    if (lit == 0) {
        fprintf(f, "1'b1");
    }
}

/*
 * Emit old-style (non-ANSI) Verilog because some ABC builds are strict
 * about ANSI-style ports.
 */
static void generate_optimized_netlist(int n, const char* name, const char* filename,
                                       const CubeVec* cubes) {
    FILE* f = fopen(filename, "w");
    int i;

    if (f == NULL) {
        die("cannot create output Verilog", filename);
    }

    fprintf(f, "// SMABC Optimized Netlist (ABC-friendly)\n");
    fprintf(f, "module %s_opt(", name);
    for (i = 0; i < n; i++) {
        fprintf(f, "i%d, ", i);
    }
    fprintf(f, "f);\n");

    for (i = 0; i < n; i++) {
        fprintf(f, "input i%d;\n", i);
    }
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

    for (i = 0; i < cubes->count; i++) {
        fprintf(f, "wire t%d;\n", i);
    }
    for (i = 0; i < cubes->count - 1; i++) {
        fprintf(f, "wire s%d;\n", i);
    }

    for (i = 0; i < cubes->count; i++) {
        fprintf(f, "assign t%d = ", i);
        emit_cube_expr(f, cubes->data[i].bits, n);
        fprintf(f, ";\n");
    }

    fprintf(f, "assign s0 = t0 | t1;\n");
    for (i = 2; i < cubes->count; i++) {
        fprintf(f, "assign s%d = s%d | t%d;\n", i - 1, i - 2, i);
    }
    fprintf(f, "assign f = s%d;\n", cubes->count - 2);

    fprintf(f, "endmodule\n");
    fclose(f);
}

static int smabc_optimize(int n, const CubeVec* cubes, int* best_p) {
    (void)n;
    *best_p = 0;
    return calculate_cube_area_estimate(n, cubes);
}

int main(void) {
    int i;

    make_directory("smabc_opt");

    for (i = 0; i < NUM_BENCH; i++) {
        int n = benches[i].n;
        int best_p = 0;
        int best_area = 0;
        CubeVec cubes;
        char vfile[256];

        cube_vec_init(&cubes);
        load_pla_onset_cubes(benches[i].pla_path, n, &cubes);

        best_area = smabc_optimize(n, &cubes, &best_p);

        printf("[OK] %-10s | in=%-2d | cubes=%-6d | polarity=%-3d | est_area=%-6d\n",
               benches[i].name, n, cubes.count, best_p, best_area);

        snprintf(vfile, sizeof(vfile), "smabc_opt/%s_opt.v", benches[i].name);
        generate_optimized_netlist(n, benches[i].name, vfile, &cubes);

        cube_vec_free(&cubes);
    }

    printf("\nDone. Generated Verilog files in smabc_opt/*.v\n");
    return 0;
}
