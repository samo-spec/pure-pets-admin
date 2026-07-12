# توثيق إدارة المدفوعات في PurePetsAdmin

## 1. نظرة عامة

هذا المستند يشرح كل ما تم إنجازه داخل تطبيق `PurePetsAdmin` بخصوص قسم إدارة المدفوعات، مع توضيح التحسينات الأمنية، تكامل Firebase، وسلسلة الإصلاحات التي تمت لاحقًا لتثبيت البناء وجعل مسار الإدارة أقرب لوضع الإنتاج.

النطاق كان مخصصًا لتطبيق الإدارة فقط.

## 2. النتيجة الرئيسية

تم إنشاء قسم كامل لإدارة المدفوعات داخل تطبيق الإدارة بحيث يستطيع الأدمن:

- عرض جميع الطلبات المرتبطة بالدفع
- البحث بواسطة رقم الطلب أو المستخدم أو طريقة الدفع
- التصفية حسب الحالة أو التاريخ أو نوع الدفع
- فتح صفحة تفاصيل كاملة للطلب/الدفع
- مراجعة الـ timeline وسجل الأحداث
- اعتماد الطلبات عند الحاجة
- إلغاء الطلبات
- معالجة حالات الإرجاع والاسترداد
- متابعة حالات `pending` و`paid` و`failed` و`cancelled` و`refunded` و`partially_refunded`
- مراجعة سجل إجراءات الأدمن على كل عملية حساسة

## 3. الموديول الجديد الخاص بالمدفوعات

تمت إضافة موديول جديد داخل:

- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementModels.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementModels.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementService.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementService.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementViewController.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementViewController.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentDetailsViewController.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentDetailsViewController.m`

### 3.1 الموديلات التي تمت إضافتها

تمت إضافة موديلات تغطي:

- `PPPaymentManagementFilters`
  - نص البحث
  - فلتر الحالة
  - فلتر نوع الدفع
  - فلتر التاريخ

- `PPPaymentAdminRecord`
  - بيانات الطلب الأساسية
  - بيانات المستخدم
  - مزود الدفع ونوعه
  - الحالة الخام للطلب/الدفع
  - إشارات الاسترداد والإرجاع
  - Snapshot للعناصر
  - Snapshot للشحن
  - حالات خصم المخزون وإرجاعه
  - ملخصات الطلبات الفرعية مثل refund/return
  - أحداث الـ timeline
  - سجل الـ audit

- `PPPaymentAdminSupportRequest`
  - تفاصيل طلبات refund / return / support
  - الحالة الحالية
  - النتيجة النهائية
  - المرفقات
  - بيانات المراجعة الإدارية
  - بيانات الحل
  - أحداث الطلب

- `PPPaymentAdminTimelineEvent`
  - سجل الأحداث الزمني

- `PPPaymentAdminAuditEntry`
  - سجل إجراءات الأدمن مع before/after state

### 3.2 الحالات المدعومة

المسار الحالي يدعم الحالات التالية:

- `pending`
- `paid`
- `failed`
- `cancelled`
- `refunded`
- `partially_refunded`

كما يدعم حالات الطلبات الفرعية مثل:

- `pending_review`
- `approved`
- `rejected`
- `completed`
- `closed`

## 4. واجهة الإدارة التي تم تسليمها

### 4.1 شاشة قائمة المدفوعات

`PPPaymentManagementViewController` يوفر:

- حقل بحث مع debounce
- Action sheet للفلاتر
- فلتر الحالة
- فلتر طريقة الدفع
- فلتر المدة الزمنية
- إعادة ضبط الفلاتر
- قسم ملخص يوضح عدد النتائج والحالة الحالية للفلاتر
- Pagination
- Pull to refresh
- حالات loading وempty وerror بشكل واضح

### 4.2 شاشة التفاصيل

`PPPaymentDetailsViewController` يوفر:

- قسم Overview
- قسم Admin Actions
- قسم Items
- قسم Requests
- قسم Timeline
- قسم Audit Trail
- تحديث كامل لسجل الطلب عند الحاجة

### 4.3 حماية تجربة الاستخدام

كل العمليات الحساسة أصبحت محمية في الواجهة من خلال:

- تأكيد قبل تنفيذ العمليات الحساسة
- إلزام الأدمن بإضافة ملاحظة مختصرة
- منع تكرار الضغط أثناء التنفيذ
- رسائل نجاح وفشل وتحميل واضحة

## 5. تكامل Firebase ومسار البيانات

التكامل تم مباشرة مع Firestore داخل تطبيق الإدارة.

### 5.1 المسارات المستخدمة

المسار الإداري الحالي يعمل مع:

- `Orders/{orderId}`
- `Orders/{orderId}/events/{eventId}`
- `Orders/{orderId}/requests/{requestId}`
- `Orders/{orderId}/requests/{requestId}/events/{eventId}`
- `AdminAuditLogs/{auditId}`

### 5.2 عمليات القراءة

الخدمة تقرأ:

- الطلبات من `Orders`
- ملخصات طلبات refund/return من `requests`
- Timeline الأحداث من `events`
- أحداث الطلبات الفرعية من `requests/{requestId}/events`
- سجل الـ audit من `AdminAuditLogs`

### 5.3 عمليات الكتابة

الخدمة تكتب بشكل آمن:

- اعتماد الطلبات
- إلغاء الطلبات
- تحديثات حالات طلبات refund/return
- بيانات الاسترداد الكامل والجزئي
- تحديثات الإرجاع
- أحداث timeline للطلبات
- أحداث timeline للطلبات الفرعية
- سجلات الـ audit
- تحديثات المخزون عند الحاجة

## 6. وسائل الأمان والإنتاجية التي أضيفت

### 6.1 حماية الصلاحيات

قبل أي عملية خاصة بالمدفوعات يتم التحقق من صلاحيات الأدمن:

- عرض القائمة
- فتح التفاصيل
- اعتماد الطلب
- إلغاء الطلب
- معالجة طلب refund/return

والصلاحيات المقبولة حاليًا هي:

- `ManageStore`
- `AdminAll`

### 6.2 تقوية قواعد Firestore

تم تعديل `PurePetsAdmin/firestore.rules` بحيث:

- التحديث على `Orders` مقيد فقط بحقوق إدارة المدفوعات
- الحقول غير المسموح بتغييرها تبقى ثابتة
- التغييرات المسموحة محصورة في مجموعة حقول واضحة فقط
- إنشاء وحذف الطلبات من هذا المسار ممنوع

وبالنسبة لـ `requests`:

- التحديث مسموح فقط على الحقول الخاصة بالحالة والمراجعة والحل
- البيانات الأساسية للطلب الفرعي تبقى immutable

وبالنسبة لـ `events` و`AdminAuditLogs`:

- الكتابة create-only
- مع تحقق من شكل البيانات

### 6.3 منع الانتقالات غير الصحيحة

تمت إضافة منطق واضح لمنع:

- اعتماد طلب تم دفعه أو إلغاؤه مسبقًا
- إلغاء طلب من حالة غير قابلة للإلغاء
- تنفيذ refund على request ليس من نوع refund
- إكمال return قبل اعتماده
- أي transition غير مدعوم

### 6.4 تقليل مشاكل السباق والتكرار

كل العمليات الحساسة تنفذ داخل Firestore transactions، وبالتالي:

- يتم إعادة قراءة الحالة الفعلية قبل التعديل
- يقل خطر double approval
- يقل خطر duplicate refund
- يظل المخزون متزامنًا مع النتيجة النهائية

### 6.5 سجل التدقيق Audit Trail

كل عملية حساسة تكتب سجلًا في `AdminAuditLogs` يتضمن:

- اسم العملية
- المجال `payments`
- نوع الكيان والهوية
- رقم الطلب
- رقم الطلب الفرعي عند الحاجة
- UID الأدمن
- اسم الأدمن
- الملاحظة
- الحالة قبل التغيير
- الحالة بعد التغيير
- وقت التنفيذ

## 7. أمان المخزون

### 7.1 عند اعتماد الطلب

عند اعتماد طلب صالح:

- تتحول الحالة إلى `paid`
- تصبح `verificationStatus = verified`
- يتم تعيين `paidAt` إذا لم يكن موجودًا
- يتم خصم المخزون فقط إذا لم يكن قد خُصم مسبقًا
- إذا فشل خصم المخزون يتم إلغاء العملية بالكامل

### 7.2 عند إلغاء الطلب

عند إلغاء طلب صالح:

- تتحول الحالة إلى `cancelled`
- يتم تسجيل بيانات الإلغاء
- يتم إرجاع المخزون فقط عندما يكون ذلك مطلوبًا فعلًا

### 7.3 عند إكمال الإرجاع

عند إكمال طلب return:

- يتم تحديث حالة الطلب الفرعي
- يتم تحديث `returnStatus`
- يتم Restock للعناصر المرجعة بشكل آمن وبكمية مضبوطة

## 8. معالجة الاسترداد والإرجاع

### 8.1 الاسترداد Refund

المسار الحالي يدعم:

- Refund كامل
- Refund جزئي

وعند التنفيذ يتم تحديث:

- حالة الطلب الفرعي
- النتيجة النهائية
- `refundStatus`
- `refundAmount`
- `refundedAt`

أمان refund الجزئي:

- المبلغ يجب أن يكون أكبر من صفر
- المبلغ يجب أن يكون أقل من قيمة الطلب الكاملة

### 8.2 الإرجاع Return

المسار الحالي يدعم:

- مراجعة طلبات الإرجاع
- قبول أو رفض الطلب
- إكمال الإرجاع عند استيفاء الشروط
- Restock للعناصر المرجعة
- تحديث `returnStatus` على الطلب

## 9. دمج القسم داخل لوحة التحكم

تمت إضافة مدخل جديد داخل Dashboard:

- العنوان: `Payment Management`
- الوصف: `Review orders, refunds, returns, and payment history`

وعند الضغط عليه يتم فتح `PPPaymentManagementViewController`.

## 10. الاختبارات التي أضيفت

داخل:

- `PurePetsAdmin/PurePetsAdminTests/PurePetsAdminTests.m`

تمت إضافة اختبارات تغطي:

- اختيار workflow status الصحيح
- أولوية إشارات refund
- قواعد اعتماد الطلب
- منع refund غير الصحيح
- شروط إكمال return

## 11. إصلاحات إضافية في تطبيق الإدارة

أثناء تثبيت موديول المدفوعات ظهرت مشاكل قديمة داخل تطبيق الإدارة مرتبطة بتكامل Firebase وبناء المشروع. لذلك تم تنفيذ سلسلة إصلاحات إضافية داخل Admin app فقط.

### 11.1 إضافة Firebase compatibility layer

تمت إضافة:

- `PurePetsAdmin/PurePetsAdmin/PPFirebaseCompat.h`

الغرض منه:

- توحيد الوصول إلى Firebase داخل الكود Objective-C
- معالجة مشاكل التوافق في الـ workspace الحالي
- توفير تعريفات مفقودة يحتاجها الكود القديم

### 11.2 تنظيف الاستيرادات القديمة

تم تعديل عدد من الملفات القديمة داخل تطبيق الإدارة لتستخدم compatibility header بدل الاستيرادات الهشة المباشرة، خصوصًا في مناطق مثل:

- إدارة المستخدمين والصلاحيات
- تسجيل دخول الأدمن
- البانرز
- الإكسسوارات
- أجزاء من الـ styling والـ storage
- موديلات Firestore القديمة

### 11.3 إصلاح مشاكل بناء خاصة بالبانرز

في مرحلة المتابعة تم تنفيذ إصلاحات إضافية:

- `PPBannerViewModel.m` أصبح يستورد `PPFirebaseCompat.h` حتى يكون `FIRTimestamp` معرفًا بشكل صحيح
- `PPBannersManager.h` أصبح يمرر أنواع Firebase listener بشكل صحيح
- `PPBannersListVC.m` أصبح يستورد `PPFirebaseCompat.h` و`PPBannersManager.h` بشكل واضح

هذه الإصلاحات لم تكن جزءًا من واجهة المدفوعات نفسها، لكنها كانت ضرورية لأن الكود القديم في Admin كان يوقف بناء المشروع قبل الوصول إلى تحقق كامل من قسم المدفوعات.

## 12. الملفات الأساسية المتأثرة

ملفات المدفوعات الجديدة:

- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementModels.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementModels.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementService.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementService.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementViewController.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementViewController.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentDetailsViewController.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentDetailsViewController.m`

ملفات الدمج والدعم:

- `PurePetsAdmin/PurePetsAdmin/AdminDashboardViewController.m`
- `PurePetsAdmin/PurePetsAdminTests/PurePetsAdminTests.m`
- `PurePetsAdmin/firestore.rules`
- `PurePetsAdmin/PurePetsAdmin.xcodeproj/project.pbxproj`
- `PurePetsAdmin/PurePetsAdmin.xcodeproj/xcshareddata/xcschemes/PurePetsAdmin.xcscheme`
- `PurePetsAdmin/PurePetsAdmin/PPFirebaseCompat.h`

كما تمت تعديلات داعمة في ملفات Admin قديمة أخرى للحفاظ على قابلية البناء.

## 13. التحقق الذي تم فعليًا

تم التأكد من الآتي:

- وجود قسم إدارة المدفوعات وربطه داخل Dashboard
- وجود تحقق من الصلاحيات قبل القراءة والكتابة
- وجود transactions لعمليات approve/cancel/request resolution
- وجود تسجيل للأحداث وaudit log
- وجود قواعد Firestore تمنع التحديثات غير المسموحة
- وجود اختبارات منطق أعمال لجزء المدفوعات
- معالجة بلوكات بناء إضافية مرتبطة بـ Firebase والبانرز

## 14. الحد الحالي للتحقق

التحقق الكامل end-to-end على هذا الجهاز ما زال متوقفًا بسبب مشاكل بيئية في Xcode وليس بسبب منطق قسم المدفوعات نفسه.

المشاكل الحالية على هذا الجهاز:

- عدم استقرار CoreSimulator
- مشكلة صلاحيات/مسار DerivedData وتم الالتفاف عليها باستخدام `/tmp`
- فشل `ibtool` في ترجمة الـ storyboards بسبب:
  - `iOS 26.2 Platform Not Installed`

بالتالي لا يمكن من هذا الجهاز الجزم بأنه لا توجد أخطاء لاحقة في بقية المشروع القديم بعد مرحلة الـ storyboard، لأن البناء يتوقف مبكرًا عند تلك النقطة.

## 15. المخاطر المتبقية

المخاطر الحالية هي:

- مخاطرة بيئية: نسخة Xcode الحالية على الجهاز تفتقد المنصة/الـ runtime المطلوب
- مخاطرة كود قديم: بعد حل مشكلة البيئة قد تظهر مشاكل أخرى في ملفات Admin القديمة غير المرتبطة مباشرة بالمدفوعات
- مخاطرة تشغيلية: نجاح المسار في الإنتاج يعتمد أيضًا على تطابق شكل بيانات Firestore الفعلية مع التوقعات الحالية

## 16. الخطوة التالية المقترحة

لإكمال التحقق النهائي قبل الإطلاق:

1. تثبيت iOS platform/runtime المطلوب في Xcode.
2. إعادة تشغيل build كامل لتطبيق الإدارة.
3. تشغيل الاختبارات.
4. تنفيذ QA يدوي على بيئة Firebase تجريبية يشمل:
   - اعتماد طلب pending
   - إلغاء طلب صالح للإلغاء
   - اعتماد طلب refund
   - تنفيذ partial refund
   - اعتماد وإكمال return
   - مراجعة timeline وaudit logs

## 17. الخلاصة النهائية

ما الذي تمت إضافته:

- قسم كامل لإدارة المدفوعات داخل Admin
- قائمة مدفوعات وفلاتر وبحث وصفحة تفاصيل
- مسارات approve / cancel / refund / return
- timeline وaudit trail
- مدخل جديد داخل Dashboard
- قواعد Firestore مؤمنة لعمليات الدفع
- اختبارات لوظائف المنطق الأساسية

ما الذي تم إصلاحه:

- مشاكل تكامل Firebase داخل تطبيق الإدارة والتي كانت تعطل بناء المسار
- مشاكل توافق Objective-C مع Firebase Auth / Firestore / Functions / Storage
- مشاكل قديمة في البانرز ظهرت أثناء محاولة التحقق الكامل من البناء

المخاطر المتبقية:

- التحقق الكامل من Build ما زال محجوزًا بمشكلة بيئية في Xcode على هذا الجهاز، وبالتحديد عدم توفر منصة iOS المطلوبة لمرحلة storyboard compilation
