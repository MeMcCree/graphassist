program graphassist;
uses raylib;
type
    ELEM_IDX=0..1023;
    EMarkType = (AXIS_ORIGIN, AXIS_UNIT, GRAPH_POINT, GRAPH_LINE, GRAPH_VEC, PIPETE);
    TGraphVec = record
        s, e: TVector2; 
    end;
    TState = record
        marktype: EMarkType;
        pick_col: TColor;
        origin, unitv: TVector2;
        vecs_len: Integer;
        vecs: array of TGraphVec;
        lines_len: Integer;
        lines: array of TGraphVec;
        points_len: Integer;
        graphPoints: array of TVector2;
    end;
    TChange = record
        marktype: EMarkType;
        prevpos: TVector2;
        len: Integer;
    end;

function Change(marktype: EMarkType; prevpos: TVector2; len: Integer): TChange;
begin
    Change.marktype := marktype;
    Change.prevpos := prevpos;
    Change.len := len;
end;

function Similarity(a, b: TColor): Single;
var
    dr, dg, db: Single;
begin
    dr := (1.0 * a.r / 255.0) - (1.0 * b.r / 255.0);
    dg := (1.0 * a.g / 255.0) - (1.0 * b.g / 255.0);
    db := (1.0 * a.b / 255.0) - (1.0 * b.b / 255.0);
    Similarity := 1.0 - Sqrt(dr*dr + dg*dg + db*db) / 2.0;
end;

const
    screenWidth: Integer = 800;
    screenHeight: Integer = 450;
    title: PChar = 'Graph assist';
    MarkTypeNames: Array[AXIS_ORIGIN..PIPETE] of String = (
        'AXIS_ORIGIN',
        'AXIS_UNIT',
        'GRAPH_POINT',
        'GRAPH_LINE',
        'GRAPH_VEC',
        'PIPETE'
    );
var
    imgPath: String;
    img: TImage;
    imgTex: TTexture;
    state: TState;
    mousePos: TVector2;
    chg: TChange;
    undo_len: Integer;
    undo: array of TChange;
    i: Integer;
    x, y, besty: Integer;
    found_similar: Boolean;
    best_sim: Single;
    sim: Single;
begin
    InitWindow(screenWidth, screenHeight, title);

    if ParamCount < 1 then
    begin
        TraceLog(Ord(LOG_ERROR), 'Expected filepath');
        ExitCode := 1;
        exit;
    end;
    imgPath := paramStr(1);
    img := LoadImage(@imgPath[1]);
    if img.width = 0 then
    begin
        TraceLog(Ord(LOG_ERROR), 'Failed to load image: %s', @imgPath[1]);
        ExitCode := 1;
        exit;
    end;
    imgTex := LoadTextureFromImage(img);

    SetWindowSize(img.width, img.height);

    undo_len := 0;
    state.marktype := AXIS_ORIGIN;
    state.origin := Vector2(0.0, 0.0);
    state.unitv := Vector2(1.0, 0.0);
    state.points_len := 0;
    state.vecs_len := 0;
    state.lines_len := 0;
    state.pick_col := Color(255, 0, 255, 255);

    SetLength(undo, 1);
    SetLength(state.graphPoints, 1);
    SetLength(state.lines, 1);
    SetLength(state.vecs, 1);

    SetTargetFPS(30);

    while not WindowShouldClose() do
    begin
        if IsKeyPressed(Ord(KEY_TAB)) then
        begin
            inc(state.marktype);
            state.marktype := EMarkType(Ord(state.marktype) mod (Ord(High(EMarkType)) + 1));
        end;

        if IsKeyPressed(Ord(KEY_R)) then
        begin
            SetLength(undo, undo_len + 1);
            undo[undo_len].marktype := GRAPH_POINT;
            undo[undo_len].len := state.points_len;
            undo_len += 1;
            
            x := 0;
            while x < img.width do
            begin
                found_similar := false;
                y := 0;
                besty := 0;
                best_sim := 0.9;

                while y < img.height do
                begin
                    sim := Similarity(state.pick_col, GetImageColor(img, x, y));
                    if sim >= best_sim then
                    begin
                        besty := y;
                        best_sim := sim;
                        found_similar := true;
                    end;
                    y += 1;
                end;

                if found_similar then
                begin
                    SetLength(state.graphPoints, state.points_len + 1);
                    state.graphPoints[state.points_len] := Vector2(x, besty);
                    state.points_len += 1;
                end;

                x += Trunc((state.unitv.x - state.origin.x) / 4.0);
            end;
        end;

        if IsKeyPressed(Ord(KEY_O)) then
        begin
            i := 0;
            while i < state.points_len do
            begin
                write('(', TextFormat('%.2f, %.2f', 
                    (state.graphPoints[i].x - state.origin.x) / (state.unitv.x - state.origin.x),
                    -1.0 * (state.graphPoints[i].y - state.origin.y) / (state.unitv.y - state.origin.y)),
                    ')');
                i += 1;
            end;
            writeln();
        end;

        if IsKeyPressed(Ord(KEY_Z)) and IsKeyDown(Ord(KEY_LEFT_CONTROL)) and (undo_len > 0) then
        begin
            chg := undo[undo_len - 1];

            case chg.marktype of
                AXIS_ORIGIN: state.origin := chg.prevpos;
                AXIS_UNIT: state.unitv := chg.prevpos;
                GRAPH_POINT: state.points_len := chg.len;
                GRAPH_LINE: state.lines_len := chg.len;
                GRAPH_VEC: state.vecs_len := chg.len;
            end;

            undo_len -= 1;
        end;

        mousePos := GetMousePosition();
        if IsMouseButtonPressed(Ord(MOUSE_BUTTON_LEFT)) then
        begin
            case state.marktype of
                AXIS_ORIGIN:
                begin
                    SetLength(undo, undo_len + 1);
                    undo[undo_len].marktype := state.marktype;
                    undo[undo_len].prevpos := state.origin;
                    undo_len += 1;
                    state.origin := mousePos;
                end;
                AXIS_UNIT:
                begin
                    SetLength(undo, undo_len + 1);
                    undo[undo_len].marktype := state.marktype;
                    undo[undo_len].prevpos := state.unitv;
                    undo_len += 1;
                    state.unitv := mousePos;
                end;
                GRAPH_POINT:
                begin
                    SetLength(undo, undo_len + 1);
                    undo[undo_len].marktype := state.marktype;
                    undo[undo_len].len := state.points_len;
                    undo_len += 1;
                    SetLength(state.graphPoints, state.points_len + 1);
                    state.graphPoints[state.points_len] := mousePos;
                    state.points_len += 1;
                end;
                PIPETE:
                begin
                    state.pick_col := GetImageColor(img, Trunc(mousePos.x), Trunc(mousePos.y));
                end;
            end;
        end;

        BeginDrawing();
            ClearBackground(BLACK);
            DrawTexture(imgTex, 0, 0, WHITE);
            DrawCircleV(state.origin, 4.0, Color(255, 0, 255, 255));
            DrawLineEx(Vector2(state.origin.x - 8, state.unitv.y), 
                       Vector2(state.origin.x + 8, state.unitv.y), 2, Color(255, 0, 255, 255));
            DrawLineEx(Vector2(state.unitv.x, state.origin.y - 8), 
                       Vector2(state.unitv.x, state.origin.y + 8), 2, Color(255, 0, 255, 255));

            DrawRectangle(0, 32, 16, 16, state.pick_col);

            i := 0;
            while i < state.points_len do
            begin
                DrawCircleV(state.graphPoints[i], 4.0, Color(255, 0, 255, 255));
                i += 1;
            end;
            DrawText(TextFormat('Similarity: %.2f', Similarity(state.pick_col, GetImageColor(img, Trunc(mousePos.x), Trunc(mousePos.y)))), 0, 16, 16, BLACK);
            DrawText(TextFormat('Mode: %s', @MarkTypeNames[state.marktype][1]), 0, 0, 16, BLACK);
        EndDrawing();
    end;

    CloseWindow();
end.