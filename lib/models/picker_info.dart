class PickerInfo {
  PickerInfo({
    required this.employeeNo,
    this.name,
  });

  final String employeeNo;
  final String? name;

  factory PickerInfo.fromJson(dynamic json) {
    if (json is String) {
      return PickerInfo(employeeNo: json);
    }
    if (json is Map<String, dynamic>) {
      final emp = '${json['employeeNo'] ?? json['employee_no'] ?? json['id'] ?? ''}';
      final name = json['name']?.toString();
      return PickerInfo(
        employeeNo: emp,
        name: (name != null && name.isNotEmpty) ? name : null,
      );
    }
    return PickerInfo(employeeNo: json.toString());
  }

  String get display => [employeeNo, if (name != null) name!].join(name == null ? '' : ' - ');
}
