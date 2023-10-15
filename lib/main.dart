import 'dart:math' as math;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Desires App',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green)
        ),
        home: const MyHomePage()
      );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const MainGraphPage();
        break;
      case 1:
        page = const HistoryPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              extended: false,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home),
                  label: Text('Home'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history),
                  label: Text('History'),
                ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: (value) { // Callback that subscribes to NavigationRail. It is called everytime the user selects a destination.
                setState(() {
                  selectedIndex = value;
                });
              },
            ),
          ),
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: page,
            ),
          ),
        ],
      ),
    );
  }
}

//*********************************************************************************************
//* HISTORY PAGE                                                                              *
//*********************************************************************************************

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPage();
}

class _HistoryPage extends State<HistoryPage> {
  var infinitePos = const Offset(double.infinity, double.infinity);
  var history = <Offset>[];
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();

    return directory.path;
  }
  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/history.txt');
  }
  Future<List<Offset>> readHistory() async {
    try {
      final file = await _localFile;

      // Read the file
      final contents = await file.readAsString();
      final lines = contents.split('\n');
      // FILE FORMAT:
      // Line 1:          DateTime | e.g./  2023-10-14 20:55:09.589323 
      // Line 2: Historical Points | e.g./  [(1,2),(2,3),(3,4)]
      List<Offset> history = <Offset>[];
      RegExp matchAllNumbers = RegExp(r'([0-9]+\.[0-9])'); // RegExp to match doubles found (and slightly modified) from: https://stackoverflow.com/questions/10516967/regexp-for-a-double
      var offsets = matchAllNumbers.allMatches(lines[1]);
      for (var i = 0; i < offsets.length; i=i+2) {
        var dx = offsets.elementAt(i)[0]!;
        var dy = offsets.elementAt(i+1)[0]!;
        history.add(Offset(double.parse(dx), double.parse(dy)));
      }
      return history;
    } catch (e) {
      // If encountering an error, return an empty list
      return <Offset>[];
    }
  }  

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Offset>>(
        future: readHistory(), 
        builder: (BuildContext context, AsyncSnapshot<List<Offset>> snapshot) {
          Widget chosenChild;
          if (snapshot.hasData) {
            chosenChild = CustomPaint(
              size: Size.infinite,
              foregroundPainter: DotPainter(infinitePos),
              painter: GraphPainter(snapshot.data!, 1, infinitePos, infinitePos),
              child: Container(),
            );
          }
          else if (snapshot.hasError) {
            chosenChild = Text('Error: ${snapshot.error}');          } 
          else {
            chosenChild = const CircularProgressIndicator(
              semanticsLabel: 'Loading data',
            );
          }
          return Scaffold(
            body: Center(
                child: SizedBox(
                  width: null,
                  height: null,
                  child: chosenChild,
                ),
              ),
          );
        }
      );
  }
}


//*********************************************************************************************
//* Main Graph Page                                                                           *
//*********************************************************************************************

class MainGraphPage extends StatefulWidget {
  const MainGraphPage({super.key});

  @override
  State<MainGraphPage> createState() => _MainGraphPageState();
}

class _MainGraphPageState extends State<MainGraphPage> {
  var kCanvasSize = double.infinity; // canvas size of graph
  var selectedIndex = 0;
  var history = <Offset>[];
  var dotPos = const Offset(double.infinity, double.infinity);
  var mode = 1;
  var cursorStartPos = const Offset(double.infinity, double.infinity);
  var cursorEndPos = const Offset(double.infinity, double.infinity);
  var resetPanFlag = false;
  var dotsMarkedForDeletion = <Offset>[];
  var enterKeyActivator = const SingleActivator(LogicalKeyboardKey.enter);
  var ctrlSKeyActivator = const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: false);
  var ctrlSAndShiftKeyActivator = const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true);
  var saveState = 0;
  String? currentFileName;
  Future<String> get _localPath async { 
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
  Future<File?> get _localFile async {
    final localpath = await _localPath;
    final path = (currentFileName == null || saveState == 1) ? await FilePicker.platform.saveFile(
      dialogTitle: 'Please select an output file:',
      fileName: currentFileName ?? 'Untitled',
      initialDirectory: localpath) : p.join(localpath, currentFileName);
    return File('$path');
  }
  Future<File?> _writeHistory(List<Offset> history) async {
    final file = await _localFile;
    if (file == null) {
      return null;
    }
    final now = DateTime.now();
    var writeOut = '${now.toString()}\n'; 
    writeOut = '$writeOut['; // [
    for (var i = 0; i < history.length; i++) {
      var pos = history[i];
      if (i == 0) {
        writeOut = history.length == 1 ? '$writeOut$pos' : '$writeOut$pos,'; // if only 1 element: [(1,2) else: [(1,2),
      }
      else if (i == history.length - 1) {
        writeOut = '$writeOut$pos'; // [(1,2),(2,3),(3,4)
      }
      else {
        writeOut = '$writeOut$pos,'; // [(1,2),(2,3),
      }
    }
    writeOut = '$writeOut]'; // [(1,2),(2,3),(3,4)]
    currentFileName = p.split(file.path).lastOrNull;
    return file.writeAsString(writeOut, 
    mode: FileMode.write,
    encoding: utf8,
    flush: true);
  }

  void _handleClick(TapDownDetails details) {
    if (mode == 1) {
      history.add(details.localPosition);
    }
    else if (mode == 2) {
      cursorStartPos = const Offset(double.infinity, double.infinity);
      cursorEndPos = const Offset(double.infinity, double.infinity);
      resetPanFlag = false;
    }
  }
  void _handlePanUpdate(DragUpdateDetails details) {
    if (mode == 2) {
      if (resetPanFlag || cursorStartPos.isInfinite) {
        cursorStartPos = details.localPosition;
        resetPanFlag = false;
      }
      else{
        cursorEndPos = details.localPosition;
        final path = Path();
        path.moveTo(cursorStartPos.dx, cursorStartPos.dy);
        path.lineTo(cursorStartPos.dx, cursorEndPos.dy);
        path.lineTo(cursorEndPos.dx, cursorEndPos.dy);
        path.lineTo(cursorEndPos.dx, cursorStartPos.dy);
        path.close();
        for (var pos in history) {
          if (path.contains(pos)) {
            dotsMarkedForDeletion.add(pos);
          }
        }
      }
    }
  }
  void _handlePanEnd(DragEndDetails details) {
    resetPanFlag = true;
  }
  void _pressButton(int newMode){
    switch (newMode) {
      case 1:
        mode = newMode;
      case 2:
        mode = newMode;
      default:
        throw UnimplementedError('no mode for $newMode');
    }
  }

  void _deletePoints() {
    if (mode == 2) {
      for (var dot in dotsMarkedForDeletion) {
          history.remove(dot);
      }
      dotsMarkedForDeletion.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(icon: Icon(mode == 1 ? Icons.add_circle : Icons.add_circle_outline), tooltip: 'Add Points', onPressed: () => setState(() => _pressButton(1))),
            IconButton(icon: Icon(mode == 2 ? Icons.remove_circle : Icons.remove_circle_outline), tooltip: 'Remove Points', onPressed: () => setState(() => _pressButton(2))),
          ],
        ),
        centerTitle: true,
      ),
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback> {
          enterKeyActivator: () { 
            setState(() => _deletePoints());
          },
          ctrlSKeyActivator: () {
            saveState = 0; 
            _writeHistory(history);
          },
          ctrlSAndShiftKeyActivator: () {
            saveState = 1; 
            _writeHistory(history);
          },
        },
        child: Focus( 
          autofocus: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Center(
              child: SizedBox( // Use null to indicate there is no constraint to the size
                width: null,
                height: null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails details) => setState(() {
                    _handleClick(details);
                  }),
                  onPanUpdate: (DragUpdateDetails details) => setState(() {
                    _handlePanUpdate(details);
                  }),
                  onPanEnd: _handlePanEnd,
                  child: CustomPaint(
                    size: Size.infinite,
                    foregroundPainter: DotPainter(dotPos),
                    painter: GraphPainter(history, mode, cursorStartPos, cursorEndPos),
                    child: Container(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DotPainter extends CustomPainter {
  final Offset pos;

  DotPainter(this.pos);

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.fill
      ..strokeWidth = 15;
    canvas.drawCircle(pos, 15, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}

class GraphPainter extends CustomPainter {
  var history = <Offset>[];
  var mode = 1;
  // Use CursorStart and CursorEnd to paint a delete box if in paintRemoveMode
  var cursorStartPos = const Offset(double.infinity, double.infinity);
  var cursorEndPos = const Offset(double.infinity, double.infinity);

  GraphPainter(this.history, this.mode, this.cursorStartPos, this.cursorEndPos);

  @override
  void paint(Canvas canvas, Size size) {
    switch (mode) {
      case 1:
        paintAddMode(canvas, size);
      case 2:
        paintRemoveMode(canvas, size);
      default:
        throw UnimplementedError('no mode for $mode');
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }

  void paintAddMode(Canvas canvas, Size size)
  {
    Paint dotPaint = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.fill
      ..strokeWidth = 15;
    _paintAxis(canvas, size);
    
    for (var pos in history) {
      canvas.drawCircle(pos, 15, dotPaint);
    }
  }

  void paintRemoveMode(Canvas canvas, Size size)
  {
    Paint rectangleOutlinePaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    Paint rectangleFillPaint = Paint()
      ..color = const Color.fromARGB(100, 244, 67, 54) // This is the same as Colors.red except the Alpha channel is modified to add transparency 
      ..style = PaintingStyle.fill
      ..strokeWidth = 3;
    Paint dotPaint = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.fill
      ..strokeWidth = 15;
    Paint highlightedDotPaint = Paint()
      ..color = Color.alphaBlend(Colors.yellow, const Color.fromARGB(100, 244, 67, 54)) // This is the same as Colors.yellow except the Alpha channel is modified to add transparency
      ..style = PaintingStyle.fill
      ..strokeWidth = 15;

    _paintAxis(canvas, size);

    final path = Path();
    path.moveTo(cursorStartPos.dx, cursorStartPos.dy);
    path.lineTo(cursorStartPos.dx, cursorEndPos.dy);
    path.lineTo(cursorEndPos.dx, cursorEndPos.dy);
    path.lineTo(cursorEndPos.dx, cursorStartPos.dy);
    path.close();
    canvas.drawPath(path, rectangleOutlinePaint);
    canvas.drawPath(path, rectangleFillPaint);

    for (var pos in history) {
      if (path.contains(pos)) {
        canvas.drawCircle(pos, 15, highlightedDotPaint);
      }
      else {
        canvas.drawCircle(pos, 15, dotPaint);
      }
    }
  }

  void _paintAxis(Canvas canvas, Size size)
  {
    Paint crossBrush = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    Paint arrowBrush = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    const arrowAngle =  30 * math.pi / 180;
    const transformFactor = 20.0;
    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 30,
    );

    const yLabelTopText = TextSpan(
      text: 'Peace',
      style: textStyle,
    );
    const yLabelBottomText = TextSpan(
      text: 'Suffering',
      style: textStyle,
    );
    const xLabelLeftText = TextSpan(
      text: 'Pain',
      style: textStyle,
    );
    const xLabelRightText = TextSpan(
      text: 'Pleasure',
      style: textStyle,
    );

    final yLabelTopPainter = TextPainter(
      text: yLabelTopText,
      textDirection: TextDirection.ltr,
    );
    yLabelTopPainter.layout(
      minWidth: 0,
      maxWidth: size.width,
    );
    final yLabelBottomPainter = TextPainter(
      text: yLabelBottomText,
      textDirection: TextDirection.ltr,
    );
    yLabelBottomPainter.layout(
      minWidth: 0,
      maxWidth: size.width,
    );
    final xLabelLeftPainter = TextPainter(
      text: xLabelLeftText,
      textDirection: TextDirection.ltr,
    );
    xLabelLeftPainter.layout(
      minWidth: 0,
      maxWidth: size.width,
    );
    final xLabelRightPainter = TextPainter(
      text: xLabelRightText,
      textDirection: TextDirection.ltr,
    );
    xLabelRightPainter.layout(
      minWidth: 0,
      maxWidth: size.width,
    );


    final path = Path();
    final arrowSize = crossBrush.strokeWidth*7;
    final yAxisStart = Offset(size.width/2, transformFactor);
    final yAxisEnd = Offset(size.width/2, size.height-transformFactor);
    final xAxisStart = Offset(transformFactor, size.height/2);
    final xAxisEnd = Offset(size.width-transformFactor, size.height/2);
    
    final yAxisStartArrowXComp = yAxisStart.dx - yAxisEnd.dx;
    final yAxisStartArrowYComp = yAxisStart.dy - yAxisEnd.dy;
    final yAxisStartArrowAngle = math.atan2(yAxisStartArrowYComp, yAxisStartArrowXComp);
    final yAxisEndArrowXComp = yAxisEnd.dx - yAxisStart.dx;
    final yAxisEndArrowYComp = yAxisEnd.dy - yAxisStart.dy;
    final yAxisEndArrowAngle = math.atan2(yAxisEndArrowYComp, yAxisEndArrowXComp);

    final xAxisStartArrowXComp = xAxisStart.dx - xAxisEnd.dx;
    final xAxisStartArrowYComp = xAxisStart.dy - xAxisEnd.dy;
    final xAxisStartArrowAngle = math.atan2(xAxisStartArrowYComp, xAxisStartArrowXComp);
    final xAxisEndArrowXComp = xAxisEnd.dx - xAxisStart.dx;
    final xAxisEndArrowYComp = xAxisEnd.dy - xAxisStart.dy;
    final xAxisEndArrowAngle = math.atan2(xAxisEndArrowYComp, xAxisEndArrowXComp);

    final p1 = Offset(yAxisStart.dx - arrowSize * math.cos(yAxisStartArrowAngle - arrowAngle),
      yAxisStart.dy - arrowSize * math.sin(yAxisStartArrowAngle - arrowAngle));
    final p2 = Offset(yAxisStart.dx - arrowSize * math.cos(yAxisStartArrowAngle + arrowAngle),
      yAxisStart.dy - arrowSize * math.sin(yAxisStartArrowAngle + arrowAngle));
    final p3 = yAxisStart;
    final a = (p1 - p3).distance;
    final b = (p1 - p2).distance;
    final c = (p2 - p3).distance;
    final s = (a+b+c)/2;
    final area = math.sqrt((s*(s-a)*(s-b)*(s-c)));
    final height = area / (1 / 2 * b);

    // Apply new offsets after taking into account the height of each arrow which is appended to the end of the axis line
    final yAxisStartOffset = Offset(yAxisStart.dx, yAxisStart.dy + height);
    final yAxisEndOffset = Offset(yAxisEnd.dx, yAxisEnd.dy - height);
    final xAxisStartOffset = Offset(xAxisStart.dx + height, xAxisStart.dy);
    final xAxisEndOffset = Offset(xAxisEnd.dx - height, xAxisEnd.dy);

    // Draw Y Axis and apply offset for arrow
    canvas.drawLine(
      yAxisStartOffset,
      yAxisEndOffset, crossBrush);
    // Draw X Axis and apply offset for arrow
    canvas.drawLine(
      xAxisStartOffset,
      xAxisEndOffset, crossBrush);
    // Draw Y Axis Arrow at the start of the line
    path.moveTo(yAxisStart.dx - arrowSize * math.cos(yAxisStartArrowAngle - arrowAngle),
      yAxisStart.dy - arrowSize * math.sin(yAxisStartArrowAngle - arrowAngle));
    path.lineTo(yAxisStart.dx, yAxisStart.dy);
    path.lineTo(yAxisStart.dx - arrowSize * math.cos(yAxisStartArrowAngle + arrowAngle),
      yAxisStart.dy - arrowSize * math.sin(yAxisStartArrowAngle + arrowAngle));
    path.close();
    canvas.drawPath(path, arrowBrush);
    // Draw Y Axis Arrow at the end of the line
    path.moveTo(yAxisEnd.dx - arrowSize * math.cos(yAxisEndArrowAngle - arrowAngle),
      yAxisEnd.dy - arrowSize * math.sin(yAxisEndArrowAngle - arrowAngle));
    path.lineTo(yAxisEnd.dx, yAxisEnd.dy);
    path.lineTo(yAxisEnd.dx - arrowSize * math.cos(yAxisEndArrowAngle + arrowAngle),
      yAxisEnd.dy - arrowSize * math.sin(yAxisEndArrowAngle + arrowAngle));
    path.close();
    // Draw X Axis Arrow at the start of the line
    canvas.drawPath(path, arrowBrush);
        path.moveTo(xAxisStart.dx - arrowSize * math.cos(xAxisStartArrowAngle - arrowAngle),
      xAxisStart.dy - arrowSize * math.sin(xAxisStartArrowAngle - arrowAngle));
    path.lineTo(xAxisStart.dx, xAxisStart.dy);
    path.lineTo(xAxisStart.dx - arrowSize * math.cos(xAxisStartArrowAngle + arrowAngle),
      xAxisStart.dy - arrowSize * math.sin(xAxisStartArrowAngle + arrowAngle));
    path.close();
    canvas.drawPath(path, arrowBrush);
    // Draw X Axis Arrow at the end of the line
    path.moveTo(xAxisEnd.dx - arrowSize * math.cos(xAxisEndArrowAngle - arrowAngle),
      xAxisEnd.dy - arrowSize * math.sin(xAxisEndArrowAngle - arrowAngle));
    path.lineTo(xAxisEnd.dx, xAxisEnd.dy);
    path.lineTo(xAxisEnd.dx - arrowSize * math.cos(xAxisEndArrowAngle + arrowAngle),
      xAxisEnd.dy - arrowSize * math.sin(xAxisEndArrowAngle + arrowAngle));
    path.close();
    canvas.drawPath(path, arrowBrush);
    // Draw Y Axis Label
    yLabelTopPainter.paint(canvas, Offset(yAxisStart.dx + b/2, yAxisStart.dy));
    yLabelBottomPainter.paint(canvas, Offset(yAxisEndOffset.dx + b/2, yAxisEndOffset.dy));
    // Draw X Axis Label
    xLabelLeftPainter.paint(canvas, Offset(xAxisStart.dx, xAxisStart.dy + b/3));
    xLabelRightPainter.paint(canvas, Offset(xAxisEndOffset.dx - xLabelRightPainter.width/2, xAxisEndOffset.dy + b/3));
  }
}