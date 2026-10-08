import 'package:flutter/material.dart';

/// 한 번에 먹는 양: 숫자 + 단위 (손채은 요청 "1회 복용량 입력")
/// 서버에는 지금처럼 dose_text 한 줄("1정", "10mL")로 저장합니다.
/// 숫자+단위로 못 나타내는 값("반 알" 등)은 '직접 입력'으로 그대로 적을 수 있어요.
class DoseField extends StatefulWidget {
  const DoseField({super.key, required this.controller, this.dense = false});

  /// 최종 문자열이 들어가는 컨트롤러 (부모가 저장할 때 이 값을 씀)
  final TextEditingController controller;
  final bool dense;

  static const units = ['정', '캡슐', '포', 'mL', '방울', '매'];
  static const custom = '직접 입력';

  /// "1정", "2.5 mL" → (1, 정) / 못 읽으면 null
  static (String, String)? parse(String text) {
    final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(\S+)\s*$').firstMatch(text);
    if (m == null) return null;
    return (m.group(1)!, m.group(2)!);
  }

  @override
  State<DoseField> createState() => _DoseFieldState();
}

class _DoseFieldState extends State<DoseField> {
  late final TextEditingController _amount;
  late String _unit;
  late final List<String> _units;

  @override
  void initState() {
    super.initState();
    final text = widget.controller.text.trim();
    final parsed = DoseField.parse(text);
    _units = [...DoseField.units];
    if (parsed != null) {
      _amount = TextEditingController(text: parsed.$1);
      _unit = parsed.$2;
      if (!_units.contains(_unit)) _units.add(_unit); // 예전에 적은 단위도 그대로 고를 수 있게
    } else if (text.isEmpty) {
      _amount = TextEditingController();
      _unit = '정';
    } else {
      _amount = TextEditingController();
      _unit = DoseField.custom; // 숫자+단위가 아닌 기존 값은 직접 입력 칸에 그대로
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _compose() {
    if (_unit == DoseField.custom) return; // 직접 입력은 controller를 바로 씀
    final a = _amount.text.trim();
    widget.controller.text = a.isEmpty ? '' : '$a$_unit';
  }

  @override
  Widget build(BuildContext context) {
    final unitPicker = DropdownButton<String>(
      value: _unit,
      underline: const SizedBox.shrink(),
      items: [...{..._units, DoseField.custom}]
          .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 17))))
          .toList(),
      onChanged: (u) {
        if (u == null) return;
        setState(() {
          if (u == DoseField.custom) {
            // 지금까지 고른 값을 직접 입력 칸으로 넘겨서 이어서 고칠 수 있게
            _unit = u;
          } else {
            _unit = u;
            _compose();
          }
        });
      },
    );

    if (_unit == DoseField.custom) {
      return Row(children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            decoration: InputDecoration(labelText: '한 번에 먹는 양', hintText: '예: 반 알', isDense: widget.dense),
          ),
        ),
        const SizedBox(width: 8),
        unitPicker,
      ]);
    }
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _compose(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          decoration: InputDecoration(labelText: '한 번에 먹는 양', hintText: '예: 1', isDense: widget.dense),
        ),
      ),
      const SizedBox(width: 8),
      unitPicker,
    ]);
  }
}
