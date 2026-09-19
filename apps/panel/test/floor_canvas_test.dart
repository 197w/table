import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/floor/floor_canvas.dart';

DiningTable _table({int w = 120, int h = 80, TableShape shape = TableShape.rect, int seats = 4}) => DiningTable(
  id: null,
  label: 'S1',
  seats: seats,
  widthCm: w,
  heightCm: h,
  zone: 'sala',
  priority: 0,
  active: true,
  xCm: 500,
  yCm: 300,
  rotation: 0,
  shape: shape,
);

void main() {
  test('krzesło odciągnięte daleko wraca do pasa przy blacie', () {
    final c = attachChair(_table(), const ChairPos(0, -900));
    expect(c.x, 0);
    expect(c.y, closeTo(-(40 + chairMaxReachCm), 0.001));
  });

  test('krzesło przeciągnięte na blat wychodzi przez najbliższą krawędź', () {
    final c = attachChair(_table(), const ChairPos(50, 5));
    expect(c.x, closeTo(60 + chairMinReachCm, 0.001));
    expect(c.y, 5);
  });

  test('krzesło przy okrągłym stoliku zostaje na okręgu wokół blatu', () {
    final c = attachChair(_table(w: 100, h: 100, shape: TableShape.round), const ChairPos(400, 0));
    expect(c.x, closeTo(50 + chairMaxReachCm, 0.001));
  });

  test('automatyczne krzesła stoją wzdłuż szerokości także przy wąskim blacie', () {
    final chairs = autoChairs(_table(w: 80, h: 120));
    expect(chairs.every((c) => c.y.abs() > 60), isTrue);
  });
}
