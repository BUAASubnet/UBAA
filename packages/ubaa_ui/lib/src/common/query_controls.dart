part of '../widgets.dart';

class _FeatureQueryControls extends StatefulWidget {
  const _FeatureQueryControls({
    required this.feature,
    required this.details,
    required this.onApply,
  });

  final FeatureId feature;
  final List<FeatureDetail> details;
  final Future<void> Function(FeatureQuery query) onApply;

  @override
  State<_FeatureQueryControls> createState() => _FeatureQueryControlsState();
}

class _FeatureQueryControlsState extends State<_FeatureQueryControls> {
  late final TextEditingController _termController;
  late final TextEditingController _dateController;
  late final TextEditingController _floorController;
  late final TextEditingController _sectionController;
  late final TextEditingController _weekController;
  late final TextEditingController _pageController;
  late final TextEditingController _sizeController;
  late final TextEditingController _premisesController;
  late final TextEditingController _storeyController;
  late final TextEditingController _areaController;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _segmentController;
  late final TextEditingController _siteController;
  late final TextEditingController _orderController;
  late final TextEditingController _bykcCourseController;
  late final TextEditingController _spocAssignmentController;
  late final TextEditingController _judgeCourseController;
  late final TextEditingController _judgeAssignmentController;
  late final TextEditingController _judgeBatchController;
  int _campus = 1;
  FeatureQueryView _scheduleView = FeatureQueryView.summary;
  FeatureQueryView _examView = FeatureQueryView.summary;
  FeatureQueryView _gradesView = FeatureQueryView.summary;
  FeatureQueryView _evaluationView = FeatureQueryView.summary;
  FeatureQueryView _libbookView = FeatureQueryView.summary;
  FeatureQueryView _bykcView = FeatureQueryView.summary;
  FeatureQueryView _ygdkView = FeatureQueryView.summary;
  FeatureQueryView _cgyyView = FeatureQueryView.summary;
  FeatureQueryView _spocView = FeatureQueryView.summary;
  FeatureQueryView _judgeView = FeatureQueryView.summary;
  FeatureQueryView _signinView = FeatureQueryView.summary;
  bool _includeExpired = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _termController = TextEditingController();
    _dateController = TextEditingController(text: _today());
    _floorController = TextEditingController();
    _sectionController = TextEditingController();
    _weekController = TextEditingController();
    _pageController = TextEditingController(text: '1');
    _sizeController = TextEditingController(text: '20');
    _premisesController = TextEditingController();
    _storeyController = TextEditingController();
    _areaController = TextEditingController();
    _startController = TextEditingController(text: '08:00');
    _endController = TextEditingController(text: '22:00');
    _segmentController = TextEditingController();
    _siteController = TextEditingController();
    _orderController = TextEditingController();
    _bykcCourseController = TextEditingController();
    _spocAssignmentController = TextEditingController();
    _judgeCourseController = TextEditingController();
    _judgeAssignmentController = TextEditingController();
    _judgeBatchController = TextEditingController();
  }

  @override
  void dispose() {
    _termController.dispose();
    _dateController.dispose();
    _floorController.dispose();
    _sectionController.dispose();
    _weekController.dispose();
    _pageController.dispose();
    _sizeController.dispose();
    _premisesController.dispose();
    _storeyController.dispose();
    _areaController.dispose();
    _startController.dispose();
    _endController.dispose();
    _segmentController.dispose();
    _siteController.dispose();
    _orderController.dispose();
    _bykcCourseController.dispose();
    _spocAssignmentController.dispose();
    _judgeCourseController.dispose();
    _judgeAssignmentController.dispose();
    _judgeBatchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ..._academicQueryFields(setState),
          ..._bykcQueryFields(setState),
          ..._libbookQueryFields(setState),
          ..._ygdkQueryFields(setState),
          ..._cgyyQueryFields(setState),
          ..._spocQueryFields(setState),
          ..._evaluationQueryFields(setState),
          ..._signinQueryFields(setState),
          ..._judgeQueryFields(setState),
          FilledButton.tonal(
            onPressed: _submitting ? null : _apply,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('应用筛选'),
          ),
        ],
      ),
    ),
  );

  Future<void> _apply() async {
    setState(() => _submitting = true);
    try {
      DateTime? date;
      int? week;
      var page = 0;
      var size = 20;
      if (widget.feature == FeatureId.schedule) {
        final rawWeek = _weekController.text.trim();
        if (rawWeek.isNotEmpty) {
          week = int.tryParse(rawWeek);
          if (week == null || week <= 0) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('周次必须是正整数。')));
            }
            return;
          }
        }
        if (_scheduleView == FeatureQueryView.scheduleWeeks ||
            _scheduleView == FeatureQueryView.scheduleWeek) {
          if (_termController.text.trim().isEmpty) {
            _showMessage('学期编码不能为空。');
            return;
          }
        }
        if (_scheduleView == FeatureQueryView.scheduleWeek && week == null) {
          _showMessage('周次不能为空。');
          return;
        }
      }
      if (widget.feature == FeatureId.classroom) {
        final rawDate = _dateController.text.trim();
        if (rawDate.isNotEmpty) {
          date = _parseDateOnly(rawDate);
          if (date == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日期格式无效，请使用 YYYY-MM-DD。')),
              );
            }
            return;
          }
        }
        final rawSection = _sectionController.text.trim();
        if (rawSection.isNotEmpty) {
          final section = int.tryParse(rawSection);
          if (section == null || section <= 0) {
            _showMessage('节次必须是正整数。');
            return;
          }
        }
      }
      if (widget.feature == FeatureId.bykc) {
        if (_bykcView == FeatureQueryView.summary) {
          page = int.tryParse(_pageController.text.trim()) ?? 0;
          size = int.tryParse(_sizeController.text.trim()) ?? 0;
          if (page <= 0 || size <= 0 || size > 100) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('页码必须从 1 开始，每页数量须为 1–100。')),
              );
            }
            return;
          }
        }
        if (_bykcView == FeatureQueryView.bykcDetail) {
          final courseId = int.tryParse(_bykcCourseController.text.trim());
          if (courseId == null || courseId <= 0) {
            _showMessage('课程 ID 必须是正整数。');
            return;
          }
        }
      }
      if (widget.feature == FeatureId.libbook) {
        if (_libbookView == FeatureQueryView.libbookAreas &&
            _premisesController.text.trim().isEmpty) {
          _showMessage('馆区 ID 不能为空。');
          return;
        }
        if ((_libbookView == FeatureQueryView.libbookAreaDetail ||
                _libbookView == FeatureQueryView.libbookSeats) &&
            _areaController.text.trim().isEmpty) {
          _showMessage('分区 ID 不能为空。');
          return;
        }
        if (_libbookView == FeatureQueryView.libbookSeats) {
          if (_segmentController.text.trim().isEmpty) {
            _showMessage('时段编号不能为空。');
            return;
          }
          final rawDate = _dateController.text.trim();
          if (rawDate.isNotEmpty) {
            date = _parseDateOnly(rawDate);
            if (date == null) {
              _showMessage('日期格式无效，请使用 YYYY-MM-DD。');
              return;
            }
          }
          if (_startController.text.trim().isEmpty ||
              _endController.text.trim().isEmpty) {
            _showMessage('开始和结束时间不能为空。');
            return;
          }
        }
        if (_libbookView == FeatureQueryView.libbookBookings) {
          page = int.tryParse(_pageController.text.trim()) ?? 0;
          size = int.tryParse(_sizeController.text.trim()) ?? 0;
          if (page <= 0 || size <= 0 || size > 100) {
            _showMessage('页码必须从 1 开始，每页数量须为 1–100。');
            return;
          }
        }
      }
      if (widget.feature == FeatureId.ygdk &&
          _ygdkView == FeatureQueryView.ygdkRecords) {
        page = int.tryParse(_pageController.text.trim()) ?? 0;
        size = int.tryParse(_sizeController.text.trim()) ?? 0;
        if (page <= 0 || size <= 0 || size > 100) {
          _showMessage('页码必须从 1 开始，每页数量须为 1–100。');
          return;
        }
      }
      if (widget.feature == FeatureId.cgyy) {
        if (_cgyyView == FeatureQueryView.cgyyDayInfo) {
          final site = int.tryParse(_siteController.text.trim());
          if (site == null || site <= 0) {
            _showMessage('站点 ID 必须是正整数。');
            return;
          }
          final rawDate = _dateController.text.trim();
          if (rawDate.isNotEmpty) {
            date = _parseDateOnly(rawDate);
            if (date == null) {
              _showMessage('日期格式无效，请使用 YYYY-MM-DD。');
              return;
            }
          }
        }
        if (_cgyyView == FeatureQueryView.cgyyOrders) {
          page = int.tryParse(_pageController.text.trim()) ?? 0;
          size = int.tryParse(_sizeController.text.trim()) ?? 0;
          if (page <= 0 || size <= 0 || size > 100) {
            _showMessage('页码必须从 1 开始，每页数量须为 1–100。');
            return;
          }
        }
        if (_cgyyView == FeatureQueryView.cgyyOrderDetail) {
          final order = int.tryParse(_orderController.text.trim());
          if (order == null || order <= 0) {
            _showMessage('订单 ID 必须是正整数。');
            return;
          }
        }
      }
      if (widget.feature == FeatureId.spoc &&
          _spocView == FeatureQueryView.spocDetail &&
          _spocAssignmentController.text.trim().isEmpty) {
        _showMessage('作业编号不能为空。');
        return;
      }
      if (widget.feature == FeatureId.judge &&
          _judgeView == FeatureQueryView.judgeDetail) {
        if (_judgeCourseController.text.trim().isEmpty) {
          _showMessage('课程编号不能为空。');
          return;
        }
        if (_judgeAssignmentController.text.trim().isEmpty) {
          _showMessage('作业编号不能为空。');
          return;
        }
      }
      List<JudgeAssignmentQueryKey> judgeKeys =
          const <JudgeAssignmentQueryKey>[];
      if (widget.feature == FeatureId.judge &&
          _judgeView == FeatureQueryView.judgeBatchDetails) {
        final parsedKeys = _parseJudgeBatchKeys();
        if (parsedKeys == null) return;
        if (parsedKeys.isEmpty) {
          _showMessage('请至少填写一项批量作业键，格式为课程编号/作业编号。');
          return;
        }
        judgeKeys = parsedKeys;
      }
      await widget.onApply(
        FeatureQuery(
          term: _termController.text.trim().isEmpty
              ? null
              : _termController.text.trim(),
          date: date,
          campus: widget.feature == FeatureId.classroom ? _campus : null,
          floorId: widget.feature == FeatureId.classroom
              ? _optionalText(_floorController)
              : null,
          section: widget.feature == FeatureId.classroom
              ? _optionalText(_sectionController)
              : null,
          week: week,
          page: page,
          size: size,
          view: widget.feature == FeatureId.exam
              ? _examView
              : widget.feature == FeatureId.schedule
              ? _scheduleView
              : widget.feature == FeatureId.grades
              ? _gradesView
              : widget.feature == FeatureId.evaluation
              ? _evaluationView
              : widget.feature == FeatureId.ygdk
              ? _ygdkView
              : widget.feature == FeatureId.cgyy
              ? _cgyyView
              : widget.feature == FeatureId.bykc
              ? _bykcView
              : widget.feature == FeatureId.spoc
              ? _spocView
              : widget.feature == FeatureId.judge
              ? _judgeView
              : widget.feature == FeatureId.signin
              ? _signinView
              : _libbookView,
          premisesId: _optionalText(_premisesController),
          storeyId: _optionalText(_storeyController),
          areaId: _optionalText(_areaController),
          startTime: _optionalText(_startController),
          endTime: _optionalText(_endController),
          segment: _optionalText(_segmentController),
          siteId: widget.feature == FeatureId.cgyy
              ? int.tryParse(_siteController.text.trim())
              : null,
          orderId: widget.feature == FeatureId.cgyy
              ? int.tryParse(_orderController.text.trim())
              : null,
          assignmentId: widget.feature == FeatureId.spoc
              ? _optionalText(_spocAssignmentController)
              : widget.feature == FeatureId.judge &&
                    _judgeView == FeatureQueryView.judgeDetail
              ? _optionalText(_judgeAssignmentController)
              : null,
          courseId:
              widget.feature == FeatureId.judge &&
                  _judgeView == FeatureQueryView.judgeDetail
              ? _optionalText(_judgeCourseController)
              : widget.feature == FeatureId.bykc
              ? _optionalText(_bykcCourseController)
              : null,
          judgeKeys: judgeKeys,
          includeExpired:
              widget.feature == FeatureId.judge &&
                  _judgeView == FeatureQueryView.summary
              ? _includeExpired
              : false,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  List<String> _detailFieldValues(String label) => widget.details
      .expand((detail) => detail.fields)
      .where((field) => field.label == label && field.value.trim().isNotEmpty)
      .map((field) => field.value.trim())
      .toSet()
      .toList(growable: false);

  Widget _valuePicker({
    required String label,
    required List<String> values,
    required ValueChanged<String> onSelected,
  }) => DropdownButton<String>(
    hint: Text(label),
    onChanged: _submitting || values.isEmpty
        ? null
        : (value) {
            if (value != null) onSelected(value);
          },
    items: values
        .map(
          (value) => DropdownMenuItem<String>(value: value, child: Text(value)),
        )
        .toList(growable: false),
  );

  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDateOnly(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year != year ||
        parsed.month != month ||
        parsed.day != day) {
      return null;
    }
    return parsed;
  }

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  List<JudgeAssignmentQueryKey>? _parseJudgeBatchKeys() {
    final keys = <JudgeAssignmentQueryKey>[];
    for (final rawLine in _judgeBatchController.text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf('/');
      if (separator <= 0 ||
          separator == line.length - 1 ||
          line.indexOf('/', separator + 1) != -1) {
        _showMessage('批量作业键格式无效，请使用课程编号/作业编号。');
        return null;
      }
      final courseId = line.substring(0, separator).trim();
      final assignmentId = line.substring(separator + 1).trim();
      if (courseId.isEmpty || assignmentId.isEmpty) {
        _showMessage('批量作业键格式无效，请使用课程编号/作业编号。');
        return null;
      }
      keys.add(
        JudgeAssignmentQueryKey(courseId: courseId, assignmentId: assignmentId),
      );
    }
    return List<JudgeAssignmentQueryKey>.unmodifiable(keys);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
