import 'dart:html';
import 'dart:math';
import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/conversions.dart';
import 'package:hex_guides_web/hex_algorithms.dart';

late CanvasElement canvas;
late CanvasRenderingContext2D ctx;
double hexSize = 30.0;
bool isPointyTop = true;

// UI Elements
late ButtonElement resetButton;
late SpanElement instructionTextSpan;
late SpanElement hexACoordsSpan, hexBCoordsSpan;
late UListElement lineHexListElement;

// State
Axial? selectedHexA;
Axial? selectedHexB;
List<Axial> hexesInLine = [];

// --- Canvas Drawing (adapted) ---
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
        double x = center.x + hexSize * cos(angle);
        double y = center.y + hexSize * sin(angle);
        if (i == 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
}

void drawHexFilled(Axial axial, {String fillStyle = 'blue', String? label, String labelColor = 'white'}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0));
        double x = center.x + hexSize * cos(angle);
        double y = center.y + hexSize * sin(angle);
        if (i == 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fillStyle = fillStyle;
    ctx.fill();
    ctx.stroke(); // Default border
    if (label != null) {
        ctx.fillStyle = labelColor;
        ctx.font = 'bold 12px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(label, center.x, center.y);
    }
}

void redrawCanvas() {
    ctx.clearRect(0, 0, canvas.width!, canvas.height!);
    int range = (canvas.width! / (hexSize * (isPointyTop ? sqrt(3) : 1.5))) ~/ 3 + 1;
    for (int q = -range; q <= range; q++) {
        for (int r = max(-range, -q - range); r <= min(range, -q + range); r++) {
            drawHexOutline(Axial(q,r));
        }
    }

    // Highlight hexes in the line
    for (int i = 0; i < hexesInLine.length; i++) {
        Axial hex = hexesInLine[i];
        String color = 'rgba(173, 216, 230, 0.7)'; // Light blue for line
        if (hex == selectedHexA) color = 'rgba(100, 100, 255, 0.9)'; // Blue for A
        else if (hex == selectedHexB) color = 'rgba(255, 100, 100, 0.9)'; // Red for B

        String? label;
        if (hex == selectedHexA) label = 'A';
        else if (hex == selectedHexB) label = 'B';
        // else label = i.toString(); // Optional: label intermediate hexes with index

        drawHexFilled(hex, fillStyle: color, label: label);
    }
}

void updateInfoPanel() {
    hexACoordsSpan.text = selectedHexA != null ? 'q:${selectedHexA!.q}, r:${selectedHexA!.r}' : '-';
    hexBCoordsSpan.text = selectedHexB != null ? 'q:${selectedHexB!.q}, r:${selectedHexB!.r}' : '-';

    lineHexListElement.innerHtml = ''; // Clear previous list
    if (hexesInLine.isEmpty) {
        final li = LIElement()..text = '-';
        lineHexListElement.append(li);
    } else {
        for (final hex in hexesInLine) {
            final li = LIElement()..text = 'Axial(q:${hex.q}, r:${hex.r})';
            if (hex == selectedHexA) li.style.fontWeight = 'bold';
            if (hex == selectedHexB) li.style.fontWeight = 'bold';
            lineHexListElement.append(li);
        }
    }

    if (selectedHexA == null) {
        instructionTextSpan.text = 'Click on the grid to select the start hex (A).';
    } else if (selectedHexB == null) {
        instructionTextSpan.text = 'Start hex (A) selected. Click to select end hex (B), or click A to deselect.';
    } else {
        instructionTextSpan.text = 'Line drawn from A to B. Click Reset to start over.';
    }
    redrawCanvas();
}

void handleCanvasClick(MouseEvent event) {
    final rect = canvas.getBoundingClientRect();
    final mousePos = Point((event.client.x - rect.left).toDouble(), (event.client.y - rect.top).toDouble());
    Axial clickedAxial = pixelToAxial(mousePos);

    if (selectedHexA == null) {
        selectedHexA = clickedAxial;
    } else if (selectedHexB == null) {
        if (clickedAxial == selectedHexA) {
            selectedHexA = null; // Deselect A
            hexesInLine.clear();
        } else {
            selectedHexB = clickedAxial;
            if (selectedHexA != null) { // Should always be true here
                hexesInLine = axialLineDraw(selectedHexA!, selectedHexB!);
            }
        }
    } else {
        // Both A and B are selected, do nothing until reset
    }
    updateInfoPanel();
}

void resetSelection() {
    selectedHexA = null;
    selectedHexB = null;
    hexesInLine.clear();
    updateInfoPanel();
}

void main() {
    canvas = querySelector('#hexLineCanvas') as CanvasElement;
    ctx = canvas.getContext('2d') as CanvasRenderingContext2D;

    resetButton = querySelector('#resetButton') as ButtonElement;
    instructionTextSpan = querySelector('#instructionText') as SpanElement;
    hexACoordsSpan = querySelector('#hexA_coords') as SpanElement;
    hexBCoordsSpan = querySelector('#hexB_coords') as SpanElement;
    lineHexListElement = querySelector('#lineHexList') as UListElement;

    resetButton.onClick.listen((_) => resetSelection());
    canvas.onClick.listen(handleCanvasClick);

    // Initial setup
    resetSelection();
}
