import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/bubble.dart';
import '../model_settings/model_settings_panel.dart';
import 'note_profile.dart';

class NoteProfileDialog extends StatefulWidget {
  const NoteProfileDialog({required this.bubble, super.key});
  final Bubble bubble;
  @override
  State<NoteProfileDialog> createState() => _NoteProfileDialogState();
}

class _NoteProfileDialogState extends State<NoteProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _cue,
      _detail,
      _preference,
      _title,
      _summary,
      _embedding,
      _embeddingModel;
  late bool _enabled;
  @override
  void initState() {
    super.initState();
    final p = widget.bubble.effectiveProfile;
    _cue = TextEditingController(text: '${p.cueValue}');
    _detail = TextEditingController(text: '${p.detailNeed}');
    _preference = TextEditingController(text: '${widget.bubble.preference}');
    _title = TextEditingController(text: p.cueText);
    _summary = TextEditingController(text: p.summary);
    _embedding = TextEditingController(text: jsonEncode(p.embedding));
    _embeddingModel = TextEditingController(text: p.embeddingModel);
    _enabled = widget.bubble.recommendationEnabled;
  }

  @override
  void dispose() {
    for (final c in [
      _cue,
      _detail,
      _preference,
      _title,
      _summary,
      _embedding,
      _embeddingModel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _number(String? text, double min, double max) {
    final n = double.tryParse(text ?? '');
    return n != null && n.isFinite && n >= min && n <= max ? null : '$min–$max';
  }

  String? _vector(String? text) {
    try {
      final raw = jsonDecode(text ?? '');
      if (raw is List && raw.every((n) => n is num && n.isFinite)) return null;
    } on Object {
      /* Report form validation below. */
    }
    return modelLabel(
      context,
      '请输入有限数值的 JSON 数组',
      'Enter a JSON array of finite numbers',
    );
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final p = widget.bubble.effectiveProfile;
    Navigator.pop(
      context,
      widget.bubble.copyWith(
        preference: double.parse(_preference.text),
        recommendationEnabled: _enabled,
        updatedAt: DateTime.now(),
        profile: NoteProfile(
          cueValue: double.parse(_cue.text),
          detailNeed: double.parse(_detail.text),
          cueText: _title.text.trim(),
          summary: _summary.text.trim(),
          embedding: (jsonDecode(_embedding.text) as List)
              .cast<num>()
              .map((n) => n.toDouble())
              .toList(),
          embeddingModel: _embeddingModel.text.trim(),
          analysisStatus: p.analysisStatus,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(modelLabel(context, '笔记推荐属性', 'Recommendation profile')),
    content: SizedBox(
      width: 550,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${modelLabel(context, '分析状态', 'Analysis status')}: ${widget.bubble.effectiveProfile.analysisStatus}',
              ),
              SwitchListTile(
                value: _enabled,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  modelLabel(context, '启用推荐', 'Enable recommendations'),
                ),
                onChanged: (v) => setState(() => _enabled = v),
              ),
              for (final field in [
                (_cue, 'cue_value', 0.0, 1.0),
                (_detail, 'detail_need', 0.0, 1.0),
                (_preference, 'preference', -.6, .6),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: field.$1,
                    decoration: InputDecoration(labelText: field.$2),
                    validator: (s) => _number(s, field.$3, field.$4),
                  ),
                ),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'cue_text'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _summary,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'summary'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _embeddingModel,
                decoration: const InputDecoration(labelText: 'embedding_model'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _embedding,
                maxLines: 3,
                validator: _vector,
                decoration: const InputDecoration(
                  labelText: 'embedding (JSON)',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(modelLabel(context, '取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(modelLabel(context, '保存', 'Save')),
      ),
    ],
  );
}
