import 'package:belatuk_http_server/src/has_current_iterator.dart';
import 'package:test/test.dart';

void main() {
  const mockFirstItem = 'foo';
  const mockLastItem = 'bar';
  const mockItems = [mockFirstItem, mockLastItem];
  group('When testing hasCurrent', () {
    test('should return false to start', () {
      final hasCurrentIterator = HasCurrentIterator(mockItems.iterator);
      expect(hasCurrentIterator.hasCurrent, isFalse);
    });

    group('With a single item list', () {
      const mockSingleList = [mockFirstItem];
      test('Should return true.', () {
        final hasCurrentIterator = HasCurrentIterator(mockSingleList.iterator);
        hasCurrentIterator.moveNext();
        expect(hasCurrentIterator.hasCurrent, isTrue);
      });
    });

    group('with an empty list', () {
      test('should return false.', () {
        final hasCurrentIterator = HasCurrentIterator([].iterator);
        hasCurrentIterator.moveNext();
        expect(hasCurrentIterator.hasCurrent, isFalse);
      });
    });

    group('when iterating beyond the end of the list', () {
      test('should return false', () {
        final hasCurrentIterator = HasCurrentIterator(mockItems.iterator);
        hasCurrentIterator.moveNext();
        hasCurrentIterator.moveNext();
        hasCurrentIterator.moveNext();
        expect(hasCurrentIterator.hasCurrent, isFalse);
      });
    });
  });

  group('When testing current', () {
    test('should return current item', () {
      final hasCurrentIterator = HasCurrentIterator(mockItems.iterator);
      hasCurrentIterator.moveNext();
      expect(
          hasCurrentIterator.current, allOf(isNotEmpty, equals(mockFirstItem)));
    });

    test('should return last item item', () {
      final hasCurrentIterator = HasCurrentIterator(mockItems.iterator);
      hasCurrentIterator.moveNext();
      hasCurrentIterator.moveNext();
      expect(
          hasCurrentIterator.current, allOf(isNotEmpty, equals(mockLastItem)));
    });
  });

  group('When testing moveNext', () {
    test('should return true', () {
      final hasCurrentIterator = HasCurrentIterator(mockItems.iterator);
      expect(hasCurrentIterator.moveNext(), isTrue);
    });

    test('should return false', () {
      final hasCurrentIterator = HasCurrentIterator(mockItems.iterator);
      hasCurrentIterator.moveNext();
      hasCurrentIterator.moveNext();
      expect(hasCurrentIterator.moveNext(), isFalse);
    });
  });
}
