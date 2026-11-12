import 'package:delegate_app/features/tasks/domain/task_image_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('falls back to the legacy single imagePath', () {
    expect(resolveTaskImagePaths(imagePath: 'task_images/c1/s/task_s_1.jpg'), [
      'task_images/c1/s/task_s_1.jpg',
    ]);
  });

  test('prefers imagePaths and caps at 3, dropping blanks and duplicates', () {
    expect(
      resolveTaskImagePaths(
        imagePath: 'legacy.jpg',
        imagePaths: ['a.jpg', 'a.jpg', '', 'b.jpg', 'c.jpg', 'd.jpg'],
      ),
      ['a.jpg', 'b.jpg', 'c.jpg'],
    );
    expect(kMaxTaskImages, 3);
  });

  test('empty inputs yield an empty list', () {
    expect(resolveTaskImagePaths(), isEmpty);
    expect(
      resolveTaskImagePaths(imagePath: '  ', imagePaths: const []),
      isEmpty,
    );
  });
}
