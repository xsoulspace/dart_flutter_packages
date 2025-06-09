import 'dart:html';
import 'dart:math';
import 'dart:collection'; // For Queue (FIFO) in BFS

import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/offset.dart' as offset_lib;
import 'package:hex_guides_web/conversions.dart';
import 'package:hex_guides_web/hex_algorithms.dart';

late CanvasElement canvas;
late CanvasRenderingContext2D ctx;
double hexSize = 25.0;
bool isPointyTop = true;

// UI Elements
late SelectElement modeSelect;
// Map Storage UI
late DivElement mapStorageControlsDiv, mapStorageInfoPanelDiv;
late SpanElement currentHexInfoSpan, msAxialSpan, msCubeSpan, msOddRSpan, msArrayIndexSpan, msHashKeySpan;
// Pathfinding UI
late DivElement pathfindingControlsDiv, pathfindingInfoPanelDiv;
late ButtonElement setStartButton, setEndButton, toggleObstacleButton, findPathButton, resetPathButton;
late SpanElement pfInstructionTextSpan, pfStartSpan, pfEndSpan, pfObstaclesCountSpan, pfPathLengthSpan, pfStatusSpan;


// State
String currentGuideMode = 'map_storage';
String currentPfSelectionMode = 'none';

Axial? hoveredHex;
Axial? pfStartHex;
Axial? pfEndHex;
Set<Axial> pfObstacles = {};
List<Axial> pfFoundPath = [];
//Set<Axial> pfOpenSetViz = {};   // Not typically visualized for BFS in the same way as A* open set
Set<Axial> pfVisitedSetViz = {}; // For visualizing BFS visited hexes


// --- Canvas Drawing ---
Point<double> hexToPixel(Axial hex) {
  double x, y;
  if (isPointyTop) {
    x = hexSize * (sqrt(3) * hex.q + sqrt(3) / 2 * hex.r);
    y = hexSize * (3.0 / 2.0 * hex.r);
  } else {
    x = hexSize * (3.0 / 2.0 * hex.q);
    y = hexSize * (sqrt(3) / 2 * hex.q + sqrt(3) * hex.r);
  }
  return Point(x + canvas.width! / 2, y + canvas.height! / 2);
}

Axial pixelToAxial(Point<double> p) {
    Point<double> pt = Point(
        (p.x - canvas.width! / 2) / hexSize,
        (p.y - canvas.height! / 2) / hexSize
    );
    double q, r;
    if (isPointyTop) {
        q = (sqrt(3)/3 * pt.x - 1.0/3 * pt.y);
        r = (2.0/3 * pt.y);
    } else {
        q = (2.0/3 * pt.x);
        r = (-1.0/3 * pt.x + sqrt(3)/3 * pt.y);
    }
    return cubeToAxial(cubeRound(q, r, -q-r));
}

void drawHexOutline(Axial axial, {String strokeStyle = '#cccccc', int lineWidth = 1}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0));
        double xPos = center.x + hexSize * cos(angle);
        double yPos = center.y + hexSize * sin(angle);
        if (i == 0) ctx.moveTo(xPos, yPos); else ctx.lineTo(xPos, yPos);
    }
    ctx.closePath();
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
}

void drawHexFilled(Axial axial, {String fillStyle = 'blue', String? label, String labelColor = 'black'}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0));
        double xPos = center.x + hexSize * cos(angle);
        double yPos = center.y + hexSize * sin(angle);
        if (i == 0) ctx.moveTo(xPos, yPos); else ctx.lineTo(xPos, yPos);
    }
    ctx.closePath();
    ctx.fillStyle = fillStyle;
    ctx.fill();
    ctx.stroke();
    if (label != null) {
        ctx.fillStyle = labelColor;
        ctx.font = 'bold 10px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(label, center.x, center.y);
    }
}

void redrawCanvas() {
    ctx.clearRect(0, 0, canvas.width!, canvas.height!);
    int gridDrawRadius = (max(canvas.width!, canvas.height!) / (hexSize * 2.0)).ceil();

    for (int q_ = -gridDrawRadius; q_ <= gridDrawRadius; q_++) {
        for (int r_ = max(-gridDrawRadius, -q_ - gridDrawRadius); r_ <= min(gridDrawRadius, -q_ + gridDrawRadius); r_++) {
            drawHexOutline(Axial(q_,r_));
        }
    }

    if (currentGuideMode == 'map_storage' && hoveredHex != null) {
        drawHexFilled(hoveredHex!, fillStyle: 'rgba(200, 200, 200, 0.8)');
    } else if (currentGuideMode == 'pathfinding') {
        pfVisitedSetViz.forEach((hex) => drawHexFilled(hex, fillStyle: 'rgba(200, 200, 200, 0.5)')); // Gray for visited

        pfObstacles.forEach((hex) => drawHexFilled(hex, fillStyle: 'rgba(50, 50, 50, 0.9)', label: 'X', labelColor:'white'));

        for(int i = 0; i < pfFoundPath.length; i++){
            final hex = pfFoundPath[i];
            if(hex != pfStartHex && hex != pfEndHex){
                 drawHexFilled(hex, fillStyle: 'rgba(0, 200, 0, 0.7)');
            }
        }

        if (pfStartHex != null) drawHexFilled(pfStartHex!, fillStyle: 'rgba(0, 0, 255, 0.8)', label: 'S', labelColor:'white');
        if (pfEndHex != null) drawHexFilled(pfEndHex!, fillStyle: 'rgba(255, 0, 0, 0.8)', label: 'E', labelColor:'white');
    }
}

// --- UI Update & Mode Switching ---
void updateUIVisibility() {
    mapStorageControlsDiv.style.display = (currentGuideMode == 'map_storage') ? 'block' : 'none';
    mapStorageInfoPanelDiv.style.display = (currentGuideMode == 'map_storage') ? 'block' : 'none';
    pathfindingControlsDiv.style.display = (currentGuideMode == 'pathfinding') ? 'block' : 'none';
    pathfindingInfoPanelDiv.style.display = (currentGuideMode == 'pathfinding') ? 'block' : 'none';
    redrawCanvas();
}

void handleModeChange() {
    currentGuideMode = modeSelect.value!;
    hoveredHex = null;
    currentHexInfoSpan.text = '-';
    if (currentGuideMode != 'pathfinding') resetPathfindingState();
    updateUIVisibility();
    updateMapStorageInfoPanel(null);
    updatePathfindingInfoPanel();
}

// --- Map Storage Logic ---
void updateMapStorageInfoPanel(Axial? axial) {
    hoveredHex = axial;
    if (axial == null) {
        currentHexInfoSpan.text = 'Click a hex';
        msAxialSpan.text = msCubeSpan.text = msOddRSpan.text = msArrayIndexSpan.text = msHashKeySpan.text = '-';
        return;
    }
    currentHexInfoSpan.text = 'q:${axial.q}, r:${axial.r}';
    Hex cube = axialToCube(axial);
    offset_lib.OffsetCoord oddR = axialToOddROffset(axial);
    int mapWidth = 10;
    int arrayIndex = oddR.row * mapWidth + oddR.col;

    msAxialSpan.text = 'q:${axial.q}, r:${axial.r}';
    msCubeSpan.text = 'q:${cube.q}, r:${cube.r}, s:${cube.s}';
    msOddRSpan.text = 'col:${oddR.col}, row:${oddR.row}';
    msArrayIndexSpan.text = (oddR.col >= 0 && oddR.col < mapWidth && oddR.row >=0) ? '$arrayIndex (approx)' : 'Out of example bounds';
    msHashKeySpan.text = '"${axial.q},${axial.r}"';
    redrawCanvas();
}

// --- Pathfinding Logic (BFS) ---
List<Axial> breadthFirstSearch(Axial start, Axial end, Set<Axial> obstacles) {
    final frontier = Queue<Axial>();
    frontier.add(start);

    final cameFrom = <Axial, Axial?>{};
    cameFrom[start] = null;

    pfVisitedSetViz.clear();
    pfVisitedSetViz.add(start);

    while (frontier.isNotEmpty) {
        Axial current = frontier.removeFirst();

        if (current == end) { // Path found
            List<Axial> path = [];
            Axial? temp = current;
            while (temp != null) {
                path.add(temp);
                temp = cameFrom[temp];
            }
            return path.reversed.toList();
        }

        for (int i = 0; i < 6; i++) {
            Axial neighbor = axialNeighbor(current, i);
            if (axialDistance(start, neighbor) > 50) continue;

            if (!obstacles.contains(neighbor) && !cameFrom.containsKey(neighbor)) {
                frontier.add(neighbor);
                cameFrom[neighbor] = current;
                pfVisitedSetViz.add(neighbor);
            }
        }
    }
    return []; // Path not found
}


void executePathfinding() {
    if (pfStartHex == null || pfEndHex == null) {
        pfStatusSpan.text = "Set Start and End points.";
        return;
    }
    pfStatusSpan.text = "Calculating (BFS)...";
    Future(() {
      pfFoundPath = breadthFirstSearch(pfStartHex!, pfEndHex!, pfObstacles);
      pfStatusSpan.text = pfFoundPath.isNotEmpty ? "Path found!" : "Path not found.";
      pfPathLengthSpan.text = pfFoundPath.isNotEmpty ? (pfFoundPath.length -1).toString() : "-";
      redrawCanvas();
    });
}

void resetPathfindingState() {
    pfStartHex = null;
    pfEndHex = null;
    pfObstacles.clear();
    pfFoundPath.clear();
    pfVisitedSetViz.clear();
    currentPfSelectionMode = 'none';
    updatePathfindingInfoPanel();
    redrawCanvas();
}

void updatePathfindingInfoPanel() {
    pfStartSpan.text = pfStartHex != null ? 'q:${pfStartHex!.q}, r:${pfStartHex!.r}' : 'None';
    pfEndSpan.text = pfEndHex != null ? 'q:${pfEndHex!.q}, r:${pfEndHex!.r}' : 'None';
    pfObstaclesCountSpan.text = pfObstacles.length.toString();

    if (pfFoundPath.isEmpty) {
         pfPathLengthSpan.text = "-";
    } else {
        pfPathLengthSpan.text = (pfFoundPath.length -1).toString();
    }

    String instruction = "Select an action (Set Start, Set End, Toggle Obstacle).";
    if (currentPfSelectionMode == 'set_start') instruction = "Click grid to set START point.";
    else if (currentPfSelectionMode == 'set_end') instruction = "Click grid to set END point.";
    else if (currentPfSelectionMode == 'toggle_obstacle') instruction = "Click grid to TOGGLE obstacles.";
    pfInstructionTextSpan.text = instruction;
}


// --- Main Event Handling ---
void handleCanvasClick(MouseEvent event) {
    final rect = canvas.getBoundingClientRect();
    final mousePos = Point((event.client.x - rect.left).toDouble(), (event.client.y - rect.top).toDouble());
    Axial clicked = pixelToAxial(mousePos);

    if (currentGuideMode == 'map_storage') {
        updateMapStorageInfoPanel(clicked);
    } else {
        if (currentPfSelectionMode == 'set_start') {
            pfStartHex = clicked;
            pfObstacles.remove(clicked);
        } else if (currentPfSelectionMode == 'set_end') {
            pfEndHex = clicked;
            pfObstacles.remove(clicked);
        } else if (currentPfSelectionMode == 'toggle_obstacle') {
            if (clicked != pfStartHex && clicked != pfEndHex) {
                if (pfObstacles.contains(clicked)) pfObstacles.remove(clicked);
                else pfObstacles.add(clicked);
            }
        }
        pfFoundPath.clear();
        pfVisitedSetViz.clear();
        updatePathfindingInfoPanel();
        redrawCanvas();
    }
}

void main() {
    canvas = querySelector('#hexMapPathCanvas') as CanvasElement;
    ctx = canvas.getContext('2d') as CanvasRenderingContext2D;

    modeSelect = querySelector('#mode') as SelectElement;
    mapStorageControlsDiv = querySelector('#mapStorageControls') as DivElement;
    mapStorageInfoPanelDiv = querySelector('#mapStorageInfoPanel') as DivElement;
    pathfindingControlsDiv = querySelector('#pathfindingControls') as DivElement;
    pathfindingInfoPanelDiv = querySelector('#pathfindingInfoPanel') as DivElement;

    currentHexInfoSpan = querySelector('#currentHexInfo') as SpanElement;
    msAxialSpan = querySelector('#msAxial') as SpanElement;
    msCubeSpan = querySelector('#msCube') as SpanElement;
    msOddRSpan = querySelector('#msOddR') as SpanElement;
    msArrayIndexSpan = querySelector('#msArrayIndex') as SpanElement;
    msHashKeySpan = querySelector('#msHashKey') as SpanElement;

    setStartButton = querySelector('#setStartButton') as ButtonElement;
    setEndButton = querySelector('#setEndButton') as ButtonElement;
    toggleObstacleButton = querySelector('#toggleObstacleButton') as ButtonElement;
    findPathButton = querySelector('#findPathButton') as ButtonElement;
    resetPathButton = querySelector('#resetPathButton') as ButtonElement;
    pfInstructionTextSpan = querySelector('#pfInstructionText') as SpanElement;
    pfStartSpan = querySelector('#pfStart') as SpanElement;
    pfEndSpan = querySelector('#pfEnd') as SpanElement;
    pfObstaclesCountSpan = querySelector('#pfObstaclesCount') as SpanElement;
    pfPathLengthSpan = querySelector('#pfPathLength') as SpanElement;
    pfStatusSpan = querySelector('#pfStatus') as SpanElement;

    modeSelect.onChange.listen((_) => handleModeChange());
    canvas.onClick.listen(handleCanvasClick);

    setStartButton.onClick.listen((_) { currentPfSelectionMode = 'set_start'; updatePathfindingInfoPanel(); });
    setEndButton.onClick.listen((_) { currentPfSelectionMode = 'set_end'; updatePathfindingInfoPanel(); });
    toggleObstacleButton.onClick.listen((_) { currentPfSelectionMode = 'toggle_obstacle'; updatePathfindingInfoPanel(); });
    findPathButton.onClick.listen((_) => executePathfinding());
    resetPathButton.onClick.listen((_) => resetPathfindingState());

    handleModeChange();
    updateMapStorageInfoPanel(null);
    resetPathfindingState();
}
