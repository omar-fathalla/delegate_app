import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

class StandardViolation {
  final int id;
  final String title;
  final double defaultFine;
  final String action1;
  final String? action2;
  final ViolationCategory category;

  const StandardViolation({
    required this.id,
    required this.title,
    required this.defaultFine,
    required this.action1,
    this.action2,
    required this.category,
  });
}

const List<StandardViolation> officialViolationsSchedule = [
  StandardViolation(
    id: 1,
    title: 'واقعة سرقة',
    defaultFine: 5000.0,
    action1: '5000 غرامة وبلوك أسواق',
    category: ViolationCategory.theft,
  ),
  StandardViolation(
    id: 2,
    title: 'العمل ببطاقة تعريف مخالفة',
    defaultFine: 5000.0,
    action1: '5000 غرامة',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 3,
    title: 'عمل فعل مخل داخل الفرع',
    defaultFine: 3000.0,
    action1: '3000 غرامة وبلوك أسواق',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 4,
    title: 'مشاجرة بين عميل ومندوب والمندوب على خطأ',
    defaultFine: 3000.0,
    action1: '3000 غرامة وبلوك أسواق',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 5,
    title: 'عمل بدون استخراج بطاقة تعريف من المركزية',
    defaultFine: 2000.0,
    action1: '2000 غرامة',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 6,
    title: 'البيع داخل الصالة بدون إذن تسويق أو بدون إيفنت',
    defaultFine: 2000.0,
    action1: '2000 غرامة',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 7,
    title: 'تعديل مساحات بدون إذن التسويق',
    defaultFine: 2000.0,
    action1: '2000 غرامة',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 8,
    title: 'التحدث بطريقة غير لائقة مع التسويق',
    defaultFine: 2000.0,
    action1: '2000 غرامة وبلوك من الفرع',
    action2: '5000 غرامة وبلوك أسواق',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 9,
    title: 'مشاجرة وتحدث بطريقة غير لائقة بالصالة مع الاستاف، أو مع مندوب',
    defaultFine: 1000.0,
    action1: '1000 غرامة وبلوك من الفرع',
    action2: '3000 غرامة وبلوك أسواق',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 10,
    title: 'خروج صلاحيات من المندوب',
    defaultFine: 1000.0,
    action1: '1000 غرامة وإرجاع البضاعة للشركة',
    category: ViolationCategory.dataMissing,
  ),
  StandardViolation(
    id: 11,
    title: 'تغيير صلاحية الأطباق',
    defaultFine: 500.0,
    action1: '500 غرامة وإرجاع البضاعة للشركة',
    category: ViolationCategory.dataMissing,
  ),
  StandardViolation(
    id: 12,
    title: 'استخدام من التذوق',
    defaultFine: 500.0,
    action1: '500 غرامة وبلوك من الفرع',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 13,
    title: 'تصوير بدون إذن',
    defaultFine: 500.0,
    action1: '500 غرامة',
    category: ViolationCategory.unauthorizedPhotography,
  ),
  StandardViolation(
    id: 14,
    title: 'الحضور والانصراف دون الرجوع للتسويق ودون التوقيع بالكارته',
    defaultFine: 100.0,
    action1: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 15,
    title: 'استخدام الهاتف داخل الصالة',
    defaultFine: 100.0,
    action1: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 16,
    title: 'بيع مندوب على بيعة مندوب آخر',
    defaultFine: 100.0,
    action1: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 17,
    title: 'وجود محادثات جانبية داخل الصالة',
    defaultFine: 100.0,
    action1: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 18,
    title: 'عدم ارتداء مهمات الجودة بيع مفتوح',
    defaultFine: 100.0,
    action1: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 19,
    title: 'الحصول على بريك أو إذن صلاة بدون إذن التسويق',
    defaultFine: 100.0,
    action1: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 20,
    title: 'مخالفة وقت إذن البريك وإذن الصالة',
    defaultFine: 100.0,
    action1: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 21,
    title: 'البيع بصوت عالٍ داخل الصالة',
    defaultFine: 100.0,
    action1: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 22,
    title: 'التلاعب في كارتة الحضور والانصراف',
    defaultFine: 500.0,
    action1: '500 غرامة',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 23,
    title: 'عمل بدون ارتداء بطاقة التعريف',
    defaultFine: 0.0,
    action1: 'لفت نظر',
    action2: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 24,
    title: 'عمل بدون ارتداء فيست',
    defaultFine: 0.0,
    action1: 'لفت نظر',
    action2: '100 غرامة فورية',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 25,
    title: 'تزوير شهادة صحية',
    defaultFine: 1000.0,
    action1: '1000 غرامة',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 26,
    title: 'تزوير في البرنت التأميني',
    defaultFine: 20000.0,
    action1: '20000 غرامة',
    category: ViolationCategory.protocolBreach,
  ),
  StandardViolation(
    id: 27,
    title: 'إدخال بيانات بالخطأ',
    defaultFine: 200.0,
    action1: '200 غرامة',
    category: ViolationCategory.dataMissing,
  ),
];
