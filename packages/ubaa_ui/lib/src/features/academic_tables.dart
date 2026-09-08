part of '../widgets.dart';

Future<void> _showAcademicDetails(BuildContext context, FeatureDetail detail) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('详细信息'),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .65,
            ),
            child: SingleChildScrollView(child: _AcademicCard(detail: detail)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
