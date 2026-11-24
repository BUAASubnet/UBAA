/// UBAA 跨平台共享界面组件。
library;

export 'src/features/bhpan/view.dart'
    show BhpanView, BhpanAccess, BhpanBackHandle;
export 'src/features/bhpan/write_flow.dart'
    show BhpanWriteStyle, BhpanWriteRunner;

export 'src/theme.dart';
export 'src/shared/feedback.dart';
export 'src/write_callbacks.dart';
export 'src/features/coursework/spoc_files_access.dart';
export 'src/features/coursework/course_files_view.dart'
    show CourseFilesView, uiCourseFileIcon, uiFileSize;
export 'src/widgets.dart';
export 'src/app/destination.dart';

export 'src/shared/place_memory.dart' show UiPlaceKeys;
