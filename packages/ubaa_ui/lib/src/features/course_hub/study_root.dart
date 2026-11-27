import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

Widget buildStudyRoot({
  required Widget grid,
  required ValueListenable<CourseHubSnapshot>? courseHub,
  required ValueChanged<String> onCourse,
  required ValueChanged<FeatureId> onOpenFeature,
  required Future<void> Function()? onRefresh,
  required VoidCallback onAssignments,
  required VoidCallback onSources,
}) {
  final source = courseHub;
  if (source == null) return grid;
  return Column(
    children: [
      SizedBox(
        height: 48,
        child: ValueListenableBuilder(
          valueListenable: source,
          builder: (_, snapshot, _) => ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (onRefresh != null)
                IconButton(
                  tooltip: '刷新课程中心',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              TextButton(onPressed: onAssignments, child: const Text('全部作业')),
              TextButton(onPressed: onSources, child: const Text('按来源浏览')),
              for (final course in snapshot.courses)
                TextButton(
                  onPressed: () => onCourse(course.key),
                  child: Text(course.name),
                ),
            ],
          ),
        ),
      ),
      Expanded(child: grid),
    ],
  );
}
