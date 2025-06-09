import 'dart:html';
import 'dart:math';
import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/offset.dart' as offset_lib;
import 'package:hex_guides_web/conversions.dart';
import 'package:hex_guides_web/hex_algorithms.dart'; // For cubeRound, potentially drawing

late CanvasElement canvas;
late CanvasRenderingContext2D ctx;
double hexSize = 25.0; // Smaller size for this guide's canvas
bool isPointyTop = true; // Default to pointy for visualization consistency, could be a toggle

// Input elements
late SelectElement inputTypeSelect, offsetInputTypeSelect;
late InputElement cubeQIn, cubeRIn, cubeSIn;
late InputElement axialQIn, axialRIn;
late InputElement offsetColIn, offsetRowIn;
late DivElement cubeInputGroup, axialInputGroup, offsetInputGroup;
late LabelElement offsetInputTypeLabel;
late SpanElement cubeInputError;

// Output elements
late SpanElement cubeOutSpan, axialOutSpan;
late SpanElement offsetOddROutSpan, offsetEvenROutSpan, offsetOddQOutSpan, offsetEvenQOutSpan;

// --- Canvas Drawing (adapted from main.dart) ---
Point<double> hexToPixel(Axial hex) {
  double x, y;
  // For this guide, let's keep the visualization consistently pointy or flat.
  // We can add a toggle later if needed. Assume pointy for now.
  // isPointyTop = true; // Or read from a UI element if we add one
  if (isPointyTop) {
    x = hexSize * (sqrt(3) * hex.q + sqrt(3) / 2 * hex.r);
    y = hexSize * (3.0 / 2.0 * hex.r);
  } else { // Flat top
    x = hexSize * (3.0 / 2.0 * hex.q);
    y = hexSize * (sqrt(3) / 2 * hex.q + sqrt(3) * hex.r);
  }
  return Point(x + canvas.width! / 2, y + canvas.height! / 2); // Centered
}

void drawHexOutline(Axial axial, {String strokeStyle = 'black', int lineWidth = 1}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0)); // 0.5 for pointy top, 0 for flat top
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

void drawHexFilled(Axial axial, {String fillStyle = '#cccccc'}) {
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
    ctx.stroke(); // Also draw border
}


void clearCanvas() {
    ctx.clearRect(0, 0, canvas.width!, canvas.height!);
}

void visualizeHex(Axial axial) {
    clearCanvas();
    // Draw a small context grid
    for (int q = -3; q <= 3; q++) {
        for (int r = max(-3, -q - 3); r <= min(3, -q + 3); r++) {
            if (q == 0 && r == 0) {
                 drawHexOutline(Axial(q,r), strokeStyle: '#999999'); // Origin a bit lighter
            } else {
                 drawHexOutline(Axial(q,r), strokeStyle: '#e0e0e0');
            }
        }
    }
    drawHexFilled(axial, fillStyle: 'rgba(255, 100, 100, 0.7)');
    drawHexOutline(axial, strokeStyle: 'red', lineWidth: 2);
}

void updateOutput(Hex? centralHex) {
    if (centralHex == null) {
        cubeOutSpan.text = '-';
        axialOutSpan.text = '-';
        offsetOddROutSpan.text = '-';
        offsetEvenROutSpan.text = '-';
        offsetOddQOutSpan.text = '-';
        offsetEvenQOutSpan.text = '-';
        clearCanvas();
        return;
    }

    Axial axial = cubeToAxial(centralHex);

    cubeOutSpan.text = 'q:${centralHex.q} r:${centralHex.r} s:${centralHex.s}';
    axialOutSpan.text = 'q:${axial.q} r:${axial.r}';

    offset_lib.OffsetCoord oddR = axialToOddROffset(axial);
    offsetOddROutSpan.text = 'col:${oddR.col} row:${oddR.row}';

    offset_lib.OffsetCoord evenR = axialToEvenROffset(axial);
    offsetEvenROutSpan.text = 'col:${evenR.col} row:${evenR.row}';

    offset_lib.OffsetCoord oddQ = axialToOddQOffset(axial);
    offsetOddQOutSpan.text = 'col:${oddQ.col} row:${oddQ.row}';

    offset_lib.OffsetCoord evenQ = axialToEvenQOffset(axial);
    offsetEvenQOutSpan.text = 'col:${evenQ.col} row:${evenQ.row}';

    visualizeHex(axial);
}

void onConvert() {
    Hex? sourceHex;
    cubeInputError.text = '';

    String selectedType = inputTypeSelect.value!;
    try {
        if (selectedType == 'cube') {
            int q = int.parse(cubeQIn.value!);
            int r = int.parse(cubeRIn.value!);
            // int s = int.parse(cubeSIn.value!); // s is derived or validated
            // For input, allow s to be manually set, but validate it
            int sVal = -q -r; // Calculate expected s
            if (cubeSIn.value != sVal.toString() && cubeSIn.value!.isNotEmpty) {
                 // If user entered S and it's not empty and not matching, show gentle error
                 // For now, we primarily drive off Q and R for cube input for simplicity.
                 // Or, we can enforce q+r+s=0 by recalculating one if they don't sum.
                 // Let's recalculate s based on q and r for now.
            }
            cubeSIn.value = sVal.toString();
             try {
                sourceHex = Hex(q, r, sVal);
            } catch (e) {
                cubeInputError.text = 'Cube coords must sum to 0 (q+r+s=0)';
                updateOutput(null);
                return;
            }

        } else if (selectedType == 'axial') {
            int q = int.parse(axialQIn.value!);
            int r = int.parse(axialRIn.value!);
            sourceHex = axialToCube(Axial(q, r));
        } else { // offset
            int col = int.parse(offsetColIn.value!);
            int row = int.parse(offsetRowIn.value!);
            offset_lib.OffsetCoord inputOffset = offset_lib.OffsetCoord(col, row);
            Axial tempAxial;
            String offsetType = offsetInputTypeSelect.value!;
            if (offsetType == 'odd-r') tempAxial = oddROffsetToAxial(inputOffset);
            else if (offsetType == 'even-r') tempAxial = evenROffsetToAxial(inputOffset);
            else if (offsetType == 'odd-q') tempAxial = oddQOffsetToAxial(inputOffset);
            else  tempAxial = evenQOffsetToAxial(inputOffset); // even-q
            sourceHex = axialToCube(tempAxial);
        }
    } catch (e) {
        // General parse error
        window.alert('Invalid number input. Please check your values.');
        updateOutput(null);
        return;
    }

    updateOutput(sourceHex);
}

void setupInputTypeChange() {
    String selected = inputTypeSelect.value!;
    cubeInputGroup.style.display = (selected == 'cube') ? 'block' : 'none';
    axialInputGroup.style.display = (selected == 'axial') ? 'block' : 'none';
    offsetInputGroup.style.display = (selected == 'offset') ? 'block' : 'none';
    offsetInputTypeLabel.style.display = (selected == 'offset') ? 'inline-block' : 'none';
    offsetInputTypeSelect.style.display = (selected == 'offset') ? 'inline-block' : 'none';

    // Auto-update S for cube input based on Q and R
    void updateCubeS() {
        if (inputTypeSelect.value == 'cube') {
            try {
                int q = int.parse(cubeQIn.value ?? '0');
                int r = int.parse(cubeRIn.value ?? '0');
                cubeSIn.value = (-q - r).toString();
                 cubeInputError.text = '';
            } catch (e) {
                // ignore parse error during typing
            }
        }
    }
    cubeQIn.onInput.listen((_) => updateCubeS());
    cubeRIn.onInput.listen((_) => updateCubeS());
}


void main() {
    canvas = querySelector('#hexDisplayCanvas') as CanvasElement;
    ctx = canvas.getContext('2d') as CanvasRenderingContext2D;

    inputTypeSelect = querySelector('#inputType') as SelectElement;
    offsetInputTypeSelect = querySelector('#offsetInputType') as SelectElement;
    offsetInputTypeLabel = querySelector('#offsetInputTypeLabel') as LabelElement;

    cubeInputGroup = querySelector('#cubeInputGroup') as DivElement;
    axialInputGroup = querySelector('#axialInputGroup') as DivElement;
    offsetInputGroup = querySelector('#offsetInputGroup') as DivElement;

    cubeQIn = querySelector('#cubeQ_in') as InputElement;
    cubeRIn = querySelector('#cubeR_in') as InputElement;
    cubeSIn = querySelector('#cubeS_in') as InputElement;
    axialQIn = querySelector('#axialQ_in') as InputElement;
    axialRIn = querySelector('#axialR_in') as InputElement;
    offsetColIn = querySelector('#offsetCol_in') as InputElement;
    offsetRowIn = querySelector('#offsetRow_in') as InputElement;
    cubeInputError = querySelector('#cubeInputError') as SpanElement;

    cubeOutSpan = querySelector('#cube_out') as SpanElement;
    axialOutSpan = querySelector('#axial_out') as SpanElement;
    offsetOddROutSpan = querySelector('#offset_oddr_out') as SpanElement;
    offsetEvenROutSpan = querySelector('#offset_evenr_out') as SpanElement;
    offsetOddQOutSpan = querySelector('#offset_oddq_out') as SpanElement;
    offsetEvenQOutSpan = querySelector('#offset_evenq_out') as SpanElement;

    (querySelector('#convertButton') as ButtonElement).onClick.listen((_) => onConvert());
    inputTypeSelect.onChange.listen((_) => setupInputTypeChange());

    // Initial setup
    setupInputTypeChange();
    onConvert(); // Perform initial conversion with default values
}
