#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <assert.h>
#include <raylib.h>
#include <raymath.h>

// Implementation from https://gist.github.com/rexim/b5b0c38f53157037923e7cdd77ce685d
#define da_append(xs, x)                                                             \
    do {                                                                             \
        if ((xs)->count >= (xs)->capacity) {                                         \
            if ((xs)->capacity == 0) (xs)->capacity = 256;                           \
            else (xs)->capacity *= 2;                                                \
            (xs)->items = realloc((xs)->items, (xs)->capacity*sizeof(*(xs)->items)); \
        }                                                                            \
                                                                                     \
        (xs)->items[(xs)->count++] = (x);                                            \
    } while (0)

#define MAX_ELEMENTS 1024
typedef enum {
    AXIS_ORIGIN, AXIS_UNIT, GRAPH_POINT, GRAPH_LINE, GRAPH_VEC, POINT, PIPETE, DEL, MARKTYPE_SIZE
} marktype_e;

typedef enum {
    UNDO_ORIGIN, UNDO_UNIT, UNDO_GRAPH_POINT, UNDO_LINE, UNDO_VEC, UNDO_GRAPH_POINTS, UNDO_POINT, UNDOTYPE_SIZE
} undotype_e;

typedef struct {
    undotype_e undotype;
    union {
        Vector2 prev_pos;
        int prev_len;
        int pos;
        struct {
            void* items;
            int count;
            int capacity;
        };
    };
} undo_t;

const char* marktype_names[MARKTYPE_SIZE] = {
    "Origin",
    "Unit of axis",
    "Graph point",
    "Line",
    "Vector",
    "Point",
    "Pipete",
    "Delete"
};

typedef struct {
    Vector2 start, end;
} graphvec_t;

struct {
    Vector2* items;
    int count;
    int capacity;
} graph_points = {0};

struct {
    Vector2* items;
    int count;
    int capacity;
} points = {0};

struct {
    graphvec_t* items;
    int count;
    int capacity;
} vecs = {0};

struct {
    graphvec_t* items;
    int count;
    int capacity;
} lines = {0};

struct {
    undo_t* items;
    int count;
    int capacity;
} undos = {0};

float similarity(Color a, Color b) {
    float dr, dg, db;
    dr = (a.r / 255.0f) - (b.r / 255.0f);
    dg = (a.g / 255.0f) - (b.g / 255.0f);
    db = (a.b / 255.0f) - (b.b / 255.0f);
    return (1.0f - sqrtf(dr*dr + dg*dg + db*db) / 2.0f);
}

Vector2 to_units(Vector2 origin, Vector2 unitv, Vector2 point) {
    Vector2 du = Vector2Subtract(unitv, origin);
    Vector2 dp = Vector2Subtract(point, origin);
    return (Vector2){dp.x/du.x, dp.y/du.y};
}

Vector2 from_units(Vector2 origin, Vector2 unitv, Vector2 point) {
    Vector2 du = Vector2Subtract(unitv, origin);
    return (Vector2){origin.x + point.x*du.x, origin.y + point.y*du.y};
}

Vector2 snap_to_grid(Vector2 origin, Vector2 unitv, Vector2 point) {
    Vector2 res = to_units(origin, unitv, point);
    res.x = round(res.x);
    res.y = round(res.y);
    res = from_units(origin, unitv, res);
    return res;
}

void DrawArrow(Vector2 start, Vector2 end, float thick, float arrow_size, Color col) {
    Vector2 dir, right;
    dir = Vector2Scale(Vector2Negate(Vector2Normalize(Vector2Subtract(end, start))), arrow_size);
    right = (Vector2){-dir.y, dir.x};
    DrawLineEx(start, end, thick, col);
    DrawLineEx(end, Vector2Add(Vector2Add(end, dir), right), thick, col);
    DrawLineEx(end, Vector2Add(Vector2Add(end, dir), Vector2Negate(right)), thick, col);
}

int main(int argc, char* argv[]) {
    const int screen_width = 600;
    const int screen_height = 600;
    const char* title = "Graph assist";
    InitWindow(screen_width, screen_height, title);
    SetTargetFPS(30);

    if (argc < 3) {
        fprintf(stderr, "Usage:\n");
        fprintf(stderr, "\tgraphassist <imgpath> <outpath>\n");
        return 1;
    }

    Image img = LoadImage(argv[1]);
    if (img.width == 0) {
        fprintf(stderr, "Failed to load image: %s", argv[1]);
        return 1;
    }
    Texture2D imgTex = LoadTextureFromImage(img);

    FILE* fd = fopen(argv[2], "w");
    if (!fd) {
        fprintf(stderr, "Failed to create file descriptor for: %s", argv[2]);
        return 1;
    }

    srand(time(0));

    Camera2D camera = {0};
    camera.zoom = 1.0f;
    camera.target = (Vector2){screen_width / 2.0f, screen_height / 2.0f};
    camera.offset = (Vector2){screen_width / 2.0f, screen_height / 2.0f};

    marktype_e sel_marktype = AXIS_ORIGIN;
    Color pick_col = (Color){255, 0, 255, 255};
    int is_drawing = 0;
    marktype_e draw_marktype = 0;
    Vector2 draw_startpos = {0};
    Vector2 mouse_pos = {0};
    Vector2 origin = {0};
    Vector2 unitv = {0};
    Vector2 cam_speed = {2.0f, 2.0f};
    undo_t undo = {0};
    int snapping = 1;
    int origin_set, unitv_set;
    origin_set = unitv_set = 0;

    while (!WindowShouldClose()) {
        mouse_pos = GetScreenToWorld2D(GetMousePosition(), camera);

        if (IsKeyPressed(KEY_MINUS)) {
            camera.zoom /= 2.0f;
            camera.zoom = fmax(0.125f, camera.zoom);
        } else if (IsKeyPressed(KEY_EQUAL)) {
            camera.zoom *= 2.0f;
            camera.zoom = fmin(16.0f, camera.zoom);
        }

        if (IsKeyPressed(KEY_LEFT_BRACKET)) {
            cam_speed = Vector2Scale(cam_speed, 0.5f);
        } else if (IsKeyPressed(KEY_RIGHT_BRACKET)) {
            cam_speed = Vector2Scale(cam_speed, 2.0f);
        }

        if (IsKeyDown(KEY_LEFT)) {
            camera.target.x -= cam_speed.x;
        }

        if (IsKeyDown(KEY_RIGHT)) {
            camera.target.x += cam_speed.x;
        }

        if (IsKeyDown(KEY_UP)) {
            camera.target.y -= cam_speed.y;
        }

        if (IsKeyDown(KEY_DOWN)) {
            camera.target.y += cam_speed.y;
        }

        if (!is_drawing && IsKeyPressed(KEY_ENTER) && origin_set && unitv_set) {
            fd = freopen(argv[2], "w", fd);
            printf("Points:\n");
            fprintf(fd, "Points:\n");
            for (int i = 0; i < graph_points.count; ++i) {
                Vector2 pu = to_units(origin, unitv, graph_points.items[i]);
                printf("(%.2f, %.2f)", pu.x, pu.y);
                fprintf(fd, "(%.2f, %.2f)", pu.x, pu.y);
            }
            printf("\n");
            printf("Lines:\n");
            fprintf(fd, "\n");
            fprintf(fd, "Lines:\n");
            for (int i = 0; i < lines.count; ++i) {
                Vector2 su = to_units(origin, unitv, lines.items[i].start);
                Vector2 eu = to_units(origin, unitv, lines.items[i].end);
                float dx, dy;
                float k, b;
                dx = eu.x - su.x;
                dy = eu.y - su.y;
                k = dy/dx;
                b = su.y - su.x * k;
                printf("dx: %.3f; dy: %.3f; su.x: %.3f; su.y: %.3f\n", dx, dy, su.x, su.y);
                printf("{%.3f*x + %.3f};\n", k, b);
                fprintf(fd, "{%.3f*x + %.3f};\n", k, b);
            }
            printf("Vectors:\n");
            fprintf(fd, "Vectors:\n");
            for (int i = 0; i < vecs.count; i++) {
                Vector2 su = to_units(origin, unitv, lines.items[i].start);
                Vector2 eu = to_units(origin, unitv, lines.items[i].end);
                printf("(%.3f, %.3f) -- (%.3f, %.3f);\n", su.x, su.y, eu.x, eu.y);
                fprintf(fd, "(%.3f, %.3f) -- (%.3f, %.3f);\n", su.x, su.y, eu.x, eu.y);
            }
        }

        if (!is_drawing && IsKeyPressed(KEY_TAB)) {
            sel_marktype = (sel_marktype + 1) % MARKTYPE_SIZE;
        }

        if (IsKeyPressed(KEY_S)) {
            snapping = !snapping;
        }

        if (!is_drawing && IsKeyPressed(KEY_G)) {
            undo.undotype = UNDO_GRAPH_POINTS;
            undo.items = malloc(sizeof(graph_points.items[0]) * graph_points.capacity);
            memcpy(undo.items, graph_points.items, sizeof(graph_points.items[0]) * graph_points.capacity);
            undo.count = graph_points.count;
            undo.capacity = graph_points.capacity;

            int prev_len = graph_points.count;
            for (float x = 0.0; x < img.width; x += unitv.x / 16.0f) {
                float sumy = 0.0f;
                int numy = 0;
                for (int y = 0; y < img.height; ++y) {
                    if (similarity(GetImageColor(img, x, y), pick_col) > 0.9f) {
                        sumy += y;
                        numy++;
                    }
                    if (numy) {
                        da_append(&graph_points, ((Vector2){x, sumy/numy}));
                        break;
                    }
                }
            }
            if (graph_points.count - prev_len) {
                da_append(&undos, undo);
            } else {
                free(undo.items);
            }
            TraceLog(LOG_INFO, "Added %d graph_points", graph_points.count - prev_len);
        }

        if (!is_drawing && undos.count > 0 && IsKeyPressed(KEY_Z) && IsKeyDown(KEY_LEFT_CONTROL)) {
            undo = undos.items[undos.count - 1];
            switch (undo.undotype) {
                case UNDO_ORIGIN: {
                    origin = undo.prev_pos;
                } break;
                case UNDO_UNIT: {
                    origin = undo.prev_pos;
                } break;
                case UNDO_GRAPH_POINT: {
                    for (int i = undo.pos; i < graph_points.count - 1; i++) {
                        graph_points.items[i] = graph_points.items[i + 1];
                    }
                    graph_points.count--;
                } break;
                case UNDO_VEC: {
                    vecs.count = undo.prev_len;
                } break;
                case UNDO_LINE: {
                    lines.count = undo.prev_len;
                } break;
                case UNDO_GRAPH_POINTS: {
                    free(graph_points.items);
                    graph_points.items = undo.items;
                    graph_points.count = undo.count;
                    graph_points.capacity = undo.capacity;
                } break;
                case UNDO_POINT: {
                    points.count = undo.prev_len;
                } break;
                default: assert(0 && "unreachable");
            }
            undos.count--;
        }

        if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
            if (!is_drawing) {
                switch (sel_marktype) {
                    case AXIS_ORIGIN: {
                        if (origin_set) {
                            undo.undotype = UNDO_ORIGIN;
                            undo.prev_pos = mouse_pos;
                            da_append(&undos, undo);
                        }
                        origin = mouse_pos;
                        origin_set = 1;
                    } break;
                    case AXIS_UNIT: {
                        if (unitv_set) {
                            undo.undotype = UNDO_UNIT;
                            undo.prev_pos = mouse_pos;
                            da_append(&undos, undo);
                        }
                        unitv = mouse_pos;
                        unitv_set = 1;
                    } break;
                    case GRAPH_POINT: {
                        undo.undotype = UNDO_GRAPH_POINT;
                        if (snapping && origin_set && unitv_set) {
                            mouse_pos = snap_to_grid(origin, unitv, mouse_pos);
                        }
                        da_append(&graph_points, mouse_pos);
                        int i;
                        for (i = 0; i < graph_points.count - 1; ++i) {
                            if (graph_points.items[i].x > mouse_pos.x) {
                                TraceLog(LOG_INFO, "Inserting at %d; graph_points.count: %d", i, graph_points.count);
                                Vector2 temp = mouse_pos;
                                for (int j = graph_points.count - 1; j > i; --j) {
                                    TraceLog(LOG_INFO, "Swapped %d and %d", j, j - 1);
                                    graph_points.items[j] = graph_points.items[j - 1];
                                }
                                graph_points.items[i] = temp;
                                break;
                            }
                        }
                        undo.pos = i;
                        da_append(&undos, undo);
                    } break;
                    case GRAPH_VEC: case GRAPH_LINE: {
                        is_drawing = 1;
                        draw_marktype = sel_marktype;
                        if (snapping && origin_set && unitv_set) {
                            mouse_pos = snap_to_grid(origin, unitv, mouse_pos);
                        }
                        draw_startpos = mouse_pos;
                    } break;
                    case PIPETE: {
                        pick_col = GetImageColor(img, mouse_pos.x, mouse_pos.y);
                    } break;
                    case DEL: {
                        int found = 0;
                        for (int i = 0; i < graph_points.count; ++i) {
                            if (Vector2Length(Vector2Subtract(graph_points.items[i], mouse_pos)) < 1.0f) {
                                found = 1;
                                for (int j = 0; j < undos.count; ++j) {
                                    if (undos.items[j].undotype == UNDO_GRAPH_POINT && undos.items[j].pos == i) {
                                        for (int k = j + 1; k < undos.count; ++k) {
                                            undos.items[j - 1] = undos.items[j];
                                        }
                                        undos.count--;
                                        break;
                                    }
                                }
                                for (int j = i + 1; j < graph_points.count; ++j) {
                                    graph_points.items[j - 1] = graph_points.items[j];
                                }
                                graph_points.count--;
                                break;
                            }
                        }
                        if (found) {
                            break;
                        }
                        for (int i = 0; i < points.count; ++i) {
                            if (Vector2Length(Vector2Subtract(points.items[i], mouse_pos)) < 1.0f) {
                                for (int j = 0; j < undos.count; ++j) {
                                    if (undos.items[j].undotype == UNDO_POINT && undos.items[j].pos == i) {
                                        for (int k = j + 1; k < undos.count; ++k) {
                                            undos.items[j - 1] = undos.items[j];
                                        }
                                        undos.count--;
                                        break;
                                    }
                                }
                                for (int j = i + 1; j < points.count; ++j) {
                                    points.items[j - 1] = points.items[j];
                                }
                                points.count--;
                                break;
                            }    
                        }
                    } break;
                    case POINT: {
                        undo.undotype = UNDO_POINT;
                        undo.prev_len = points.count;
                        da_append(&undos, undo);
                        if (snapping && origin_set && unitv_set) {
                            mouse_pos = snap_to_grid(origin, unitv, mouse_pos);
                        }
                        da_append(&points, mouse_pos);
                    } break;
                    default: assert(0 && "unreachable");
                }
            } else {
                is_drawing = 0;
                undo.undotype = draw_marktype;

                if (snapping && origin_set && unitv_set) {
                    mouse_pos = snap_to_grid(origin, unitv, mouse_pos);
                }
                switch (draw_marktype) {
                    case GRAPH_VEC: {
                        undo.prev_len = vecs.count;
                        da_append(&vecs, ((graphvec_t){draw_startpos, mouse_pos}));
                    } break;
                    case GRAPH_LINE: {
                        undo.prev_len = lines.count;
                        da_append(&lines, ((graphvec_t){draw_startpos, mouse_pos}));
                    } break;
                    default: assert(0 && "unreachable");
                }

                da_append(&undos, undo);
            }
        }

        BeginDrawing();
            ClearBackground(BLACK);

            BeginMode2D(camera);
                DrawTexture(imgTex, 0, 0, WHITE);
                if (origin_set) {
                    DrawCircleV(origin, 2.0, (Color){255, 0, 255, 255});
                    if (unitv_set) {
                        DrawLineEx((Vector2){origin.x - 8, unitv.y},
                                   (Vector2){origin.x + 8, unitv.y}, 2, (Color){255, 0, 255, 255});
                        DrawLineEx((Vector2){unitv.x, origin.y - 8},
                                   (Vector2){unitv.x, origin.y + 8}, 2, (Color){255, 0, 255, 255});
                    }
                }

                if (snapping && origin_set && unitv_set) {
                    mouse_pos = snap_to_grid(origin, unitv, mouse_pos);
                }

                if (is_drawing) {
                    DrawArrow(draw_startpos, mouse_pos, 1.5, 3.0, RED);
                } else if (snapping && origin_set && unitv_set) {
                    DrawCircleV(mouse_pos, 0.5f, (Color){255, 128, 128, 255});
                }

                for (int i = 0; i < graph_points.count; ++i) {
                    Color col;
                    if (Vector2Length(Vector2Subtract(mouse_pos, graph_points.items[i])) < 1.0f) {
                        col = (Color){255, 0, 0, 255};
                    } else {
                        col = (Color){255, 0, 255, 255};
                    }
                    if (i) {
                        DrawLineEx(graph_points.items[i-1], graph_points.items[i], 1.25f, (Color){255, 0, 255, 255});
                    }
                    DrawCircleV(graph_points.items[i], 1.0f, col);
                }

                for (int i = 0; i < points.count; ++i) {
                    Color col;
                    if (Vector2Length(Vector2Subtract(mouse_pos, points.items[i])) < 1.0f) {
                        col = (Color){255, 0, 0, 255};
                    } else {
                        col = (Color){255, 0, 255, 255};
                    }
                    DrawCircleV(points.items[i], 1.0f, col);
                }

                for (int i = 0; i < vecs.count; ++i) {
                    DrawArrow(vecs.items[i].start, vecs.items[i].end, 2.0, 4.0, BLUE);
                }

                for (int i = 0; i < lines.count; ++i) {
                    DrawLineEx(lines.items[i].start, lines.items[i].end, 2.0, GREEN);
                }
            EndMode2D();

            DrawRectangle(0, 48, 16, 16, pick_col);

            DrawText(TextFormat("Mode: %s", marktype_names[sel_marktype]), 0, 0, 16, (Color){255, 0, 255, 255});
            DrawText(TextFormat("Similarity: %.3f", similarity(pick_col, GetImageColor(img, mouse_pos.x, mouse_pos.y))), 0, 16, 16, (Color){255, 0, 255, 255});
            DrawText(TextFormat("Snapping: %s", (snapping ? "On" : "Off")), 0, 32, 16, (Color){255, 0, 255, 255});
        EndDrawing();
    }

    fclose(fd);
    CloseWindow();
    return 0;
}