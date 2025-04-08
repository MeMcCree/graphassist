program graphassist;
uses raylib;
type
    ELEM_IDX=0..1023;
    EMarkType = (AXIS_ORIGIN, AXIS_UNIT, GRAPH_POINT, GRAPH_LINE, GRAPH_VEC, PIPETE, DEL);
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
        drawing: Boolean;
        drawType: EMarkType;
        nGraphVec: TGraphVec;
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

procedure DrawArrow(b, e: TVector2; thick, arrowSize: Single; col: TColor);
var
    dir, right: TVector2;
begin
    dir := Vector2Scale(Vector2Negate(Vector2Normalize(Vector2Subtract(e, b))), arrowSize);
    right := Vector2(-dir.y, dir.x);
    DrawLineEx(b, e, thick, col);
    DrawLineEx(e, Vector2Add(Vector2Add(e, dir), right), thick, col);
    DrawLineEx(e, Vector2Add(Vector2Add(e, dir), Vector2Negate(right)), thick, col);
end;

const
    screenWidth: Integer = 600;
    screenHeight: Integer = 600;
    title: PChar = 'Graph assist';
    MarkTypeNames: Array[AXIS_ORIGIN..DEL] of String = (
        'Origin',
        'Unit of axis',
        'Point',
        'Line',
        'Vector',
        'Pipete',
        'Delete'
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
    found_similar: Integer;
    sumy: Single;
    sim: Single;
    k, b, dx, dy, transX, transY, etransX, etransY: Single;
    camera: TCamera2D;
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

    undo_len := 0;
    state.marktype := AXIS_ORIGIN;
    state.origin := Vector2(0.0, 0.0);
    state.unitv := Vector2(1.0, 0.0);
    state.points_len := 0;
    state.vecs_len := 0;
    state.lines_len := 0;
    state.pick_col := Color(255, 0, 255, 255);
    state.drawing := false;

    camera.target := Vector2(0.0, 0.0);
    camera.offset := Vector2(0.0, 0.0);
    camera.rotation := 0.0;
    camera.zoom := 1.0;

    SetLength(undo, 1);
    SetLength(state.graphPoints, 1);
    SetLength(state.lines, 1);
    SetLength(state.vecs, 1);

    SetTargetFPS(30);

    while not WindowShouldClose() do
    begin
        if IsKeyPressed(Ord(KEY_MINUS)) then
        begin
            camera.zoom -= 0.1;
        end;

        if IsKeyPressed(Ord(KEY_EQUAL)) then
        begin
            camera.zoom += 0.25;
        end;

        if IsKeyDown(Ord(KEY_LEFT)) then
        begin
            camera.target.x -= 2.0;
        end;

        if IsKeyDown(Ord(KEY_RIGHT)) then
        begin
            camera.target.x += 2.0;
        end;

        if IsKeyDown(Ord(KEY_UP)) then
        begin
            camera.target.y -= 2.0;
        end;

        if IsKeyDown(Ord(KEY_DOWN)) then
        begin
            camera.target.y += 2.0;
        end;

        if IsKeyPressed(Ord(KEY_TAB)) and not state.drawing then
        begin
            inc(state.marktype);
            state.marktype := EMarkType(Ord(state.marktype) mod (Ord(High(EMarkType)) + 1));
        end;

        if IsKeyPressed(Ord(KEY_R)) and not state.drawing then
        begin
            SetLength(undo, undo_len + 1);
            undo[undo_len].marktype := GRAPH_POINT;
            undo[undo_len].len := state.points_len;
            undo_len += 1;
            
            x := 0;
            while x < img.width do
            begin
                found_similar := 0;
                y := 0;
                sumy := 0.0;

                while y < img.height do
                begin
                    sim := Similarity(state.pick_col, GetImageColor(img, x, y));
                    if sim >= 0.93 then
                    begin
                        sumy += y;
                        found_similar += 1;
                    end;
                    y += 1;
                end;

                if found_similar > 0 then
                begin
                    SetLength(state.graphPoints, state.points_len + 1);
                    state.graphPoints[state.points_len] := Vector2(x, sumy / found_similar);
                    state.points_len += 1;
                end;

                x += Trunc((state.unitv.x - state.origin.x) / 8.0);
            end;
        end;

        if IsKeyPressed(Ord(KEY_O)) and not state.drawing then
        begin
            i := 0;
            write('Points: ');
            while i < state.points_len do
            begin
                transX := (state.graphPoints[i].x - state.origin.x) / (state.unitv.x - state.origin.x);
                transY := (state.graphPoints[i].y - state.origin.y) / (state.unitv.y - state.origin.y);
                write('(', TextFormat('%.3f, %.3f', 
                    transX,
                    transY),
                    ')');
                i += 1;
            end;
            writeln();

            i := 0;
            write('Vectors: ');
            while i < state.vecs_len do
            begin
                transX := (state.vecs[i].s.x - state.origin.x) / (state.unitv.x - state.origin.x);
                transY := (state.vecs[i].s.y - state.origin.y) / (state.unitv.y - state.origin.y);
                etransX := (state.vecs[i].e.x - state.origin.x) / (state.unitv.x - state.origin.x);
                etransY := (state.vecs[i].e.y - state.origin.y) / (state.unitv.y - state.origin.y);
                write('(', TextFormat('%.3f, %.3f', 
                    transX,
                    transY),
                    ') -- ');
                write('(', TextFormat('%.3f, %.3f', 
                    etransX,
                    etransY),
                    ');');
                i += 1;
            end;
            writeln();

            i := 0;
            write('Lines: ');
            while i < state.lines_len do
            begin
                transX := (state.lines[i].s.x - state.origin.x) / (state.unitv.x - state.origin.x);
                transY := (state.lines[i].s.y - state.origin.y) / (state.unitv.y - state.origin.y);
                etransX := (state.lines[i].e.x - state.origin.x) / (state.unitv.x - state.origin.x);
                etransY := (state.lines[i].e.y - state.origin.y) / (state.unitv.y - state.origin.y);
                dx := Round(etransX - transX);
                dy := Round(etransY - transY);
                k := dy/dx;
                b := transY - k * transX;
                write(TextFormat('y = %.3f*x + %.3f', k, b), '; ');
                i += 1;
            end;
            writeln();
        end;

        if IsKeyPressed(Ord(KEY_Z)) and IsKeyDown(Ord(KEY_LEFT_CONTROL)) and (undo_len > 0) and not state.drawing then
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

        mousePos := GetScreenToWorld2D(GetMousePosition(), camera);

        if IsMouseButtonPressed(Ord(MOUSE_BUTTON_LEFT)) then
        begin
            if not state.drawing then
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
                    GRAPH_LINE, GRAPH_VEC:
                    begin
                        state.drawing := true;
                        state.drawType := state.marktype;
                        state.nGraphVec.s := mousePos;
                    end;
                    PIPETE:
                    begin
                        state.pick_col := GetImageColor(img, Trunc(mousePos.x), Trunc(mousePos.y));
                    end;
                    DEL:
                    begin
                        i := 0;
                        while i < state.points_len do
                        begin
                            if Vector2Length(Vector2Subtract(state.graphPoints[i], mousePos)) < 1.25 then
                            begin
                                i += 1;
                                while i < state.points_len do
                                begin
                                    state.graphPoints[i - 1] := state.graphPoints[i];
                                    i += 1;
                                end;
                                Break;
                            end;
                            i += 1;
                        end;
                    end;
                end;
            end
            else
            begin
                state.drawing := false;
                state.nGraphVec.e := mousePos;
                case state.drawType of
                    GRAPH_VEC:
                    begin
                        SetLength(undo, undo_len + 1);
                        undo[undo_len].marktype := state.drawType;
                        undo[undo_len].len := state.vecs_len;
                        undo_len += 1;
                        SetLength(state.vecs, state.vecs_len + 1);
                        state.vecs[state.vecs_len] := state.nGraphVec;
                        state.vecs_len += 1;
                    end;
                    GRAPH_LINE:
                    begin
                        SetLength(undo, undo_len + 1);
                        undo[undo_len].marktype := state.drawType;
                        undo[undo_len].len := state.lines_len;
                        undo_len += 1;
                        SetLength(state.lines, state.lines_len + 1);
                        state.lines[state.lines_len] := state.nGraphVec;
                        state.lines_len += 1;
                    end;
                end;
            end;
        end;

        BeginDrawing();
            ClearBackground(BLACK);

            BeginMode2D(camera);
                DrawTexture(imgTex, 0, 0, WHITE);
                DrawCircleV(state.origin, 4.0, Color(255, 0, 255, 255));
                DrawLineEx(Vector2(state.origin.x - 8, state.unitv.y), 
                           Vector2(state.origin.x + 8, state.unitv.y), 2, Color(255, 0, 255, 255));
                DrawLineEx(Vector2(state.unitv.x, state.origin.y - 8), 
                           Vector2(state.unitv.x, state.origin.y + 8), 2, Color(255, 0, 255, 255));
            
                if state.drawing then
                begin
                    DrawArrow(state.nGraphVec.s, mousePos, 2.0, 4.0, RED);
                end;

                i := 0;
                while i < (state.points_len-1) do
                begin
                    DrawCircleV(state.graphPoints[i], 2.0, Color(255, 0, 255, 255));
                    DrawLineEx(state.graphPoints[i], state.graphPoints[i+1], 2.0, Color(255, 0, 255, 255));                    
                    i += 1;
                end;

                i := 0;
                while i < state.vecs_len do
                begin
                    DrawArrow(state.vecs[i].s, state.vecs[i].e, 2.0, 4.0, BLUE);
                    i += 1;
                end;

                i := 0;
                while i < state.lines_len do
                begin
                    DrawLineEx(state.lines[i].s, state.lines[i].e, 2.0, GREEN);
                    i += 1;
                end;
            EndMode2D();

            DrawRectangle(0, 32, 16, 16, state.pick_col);

            DrawText(TextFormat('Similarity: %.3f', Similarity(state.pick_col, GetImageColor(img, Trunc(mousePos.x), Trunc(mousePos.y)))), 0, 16, 16, Color(255, 0, 255, 255));
            DrawText(TextFormat('Mode: %s', @MarkTypeNames[state.marktype][1]), 0, 0, 16, Color(255, 0, 255, 255));
        EndDrawing();
    end;

    CloseWindow();
end.