import { normalizePhoneNumber } from './state.js';

const el = (id) => document.getElementById(id);
const lang = { current: 'ar' };

const labels = {
  ar: {
    title: 'طلبات الجملة',
    subtitle: 'مراجعة منظمة وموثوقة لطلبات الشركاء دون المساس بالدفع أو المخزون.',
    eyebrow: 'THE WHOLESALE DESK / مكتب مراجعة الجملة',
    headerSubtitle: 'منصة إدارة الجملة',
    authKicker: 'STAFF ACCESS CONTROL',
    auth: 'دخول الموظفين',
    authHelp: 'هذه المساحة مخصصة للموظفين المعتمدين وتتطلب تصريح بيع الجملة في الفرع المحدد.',
    login: 'دخول',
    logout: 'خروج',
    store: 'المتجر',
    storeNavText: 'بوابة المتجر',
    storeNavTitle: 'الانتقال إلى متجر الجملة',
    branch: 'الفرع',
    status: 'الحالة',
    count: 'طلب',
    refresh: 'تحديث',
    pending: 'بانتظار المراجعة',
    accepted: 'جاهز للمعالجة',
    rejected: 'مرفوض',
    cancelled: 'ملغي من العميل',
    policy: 'قبول الطلب لا يعتبر عملية بيع أو قبضاً أو حجزاً للمخزون؛ يجب إكمال البيع الفعلي حصرياً عبر نقطة البيع (POS) المصرح بها.',
    empty: 'لا توجد طلبات ضمن هذا الاختيار.',
    unauthorized: 'لا تملك صلاحيات فروع الجملة. اطلب من مسؤول النظام مراجعة الصلاحيات.',
    unavailable: 'تعذر تحميل الطلبات. تحقق من الاتصال وحاول مرة أخرى.',
    accept: 'قبول للمعالجة',
    reject: 'رفض الطلب',
    quantity: 'العبوات',
    total: 'الإجمالي التقديري',
    notes: 'ملاحظات المراجعة (اختياري)',
    notesPlaceholder: 'أضف أي ملاحظات موجهة للفرع أو العميل...',
    submit: 'تأكيد القرار',
    processing: 'جارٍ التنفيذ...',
    loginFailed: 'بيانات الدخول غير صحيحة أو الخدمة غير متاحة.',
    ready: 'جاهز لمراجعة طلبات الفرع',
    readyAuthorized: 'جاهز لمراجعة طلبات الفرع (صلاحية قيادية معتمدة)',
    review: 'قرار المراجعة',
    reviewKicker: 'WHOLESALE REVIEW / قرار المراجعة',
    error: 'تعذر حفظ القرار. تحقق من الحالة والصلاحيات.',
    success: 'تم تسجيل قرار المراجعة بنجاح',
    customer: 'حساب العميل',
    googleSignIn: 'المتابعة باستخدام Google',
    appleSignIn: 'المتابعة باستخدام Apple',
    orDivider: 'أو تسجيل الدخول المباشر',
    tabEmail: 'البريد الإلكتروني',
    tabPhone: 'رقم الهاتف',
    emailLabel: 'البريد الإلكتروني',
    passwordLabel: 'كلمة المرور',
    phoneNumber: 'رقم الهاتف',
    sendCode: 'إرسال رمز التحقق (SMS)',
    codeSentTo: 'تم إرسال رمز التحقق إلى:',
    changePhone: 'تغيير الرقم',
    smsCode: 'رمز التحقق (6 أرقام)',
    verifyCode: 'تأكيد الرمز والدخول',
    resendCode: 'إعادة إرسال الرمز',
    codeResent: 'تمت إعادة إرسال رمز التحقق',
    invalidPhone: 'يرجى إدخال رقم هاتف صحيح (مثال: +97455551234)',
    invalidCode: 'رمز التحقق غير صحيح، يرجى التأكد وإعادة المحاولة.',
    phoneQuota: 'تم تجاوز الحد المسموح لإرسال الرسائل، حاول لاحقاً.',
    authFailed: 'تعذر تسجيل الدخول. تحقق من بياناتك أو اتصالك.',
    previewDomainBlocked: 'نطاق المعاينة غير مضاف إلى نطاقات OAuth في Firebase Console. يرجى تسجيل الدخول بالبريد الإلكتروني أو الهاتف في بيئة المعاينة.',
    themeToggle: 'تبديل المظهر',
    signedIn: 'تم تسجيل الدخول بنجاح',
    operatorClearance: 'بيانات المشغل والصلاحيات',
    verifiedTag: 'موثق رسمي',
    copyUidTitle: 'انقر لنسخ معرّف المشغل',
    copied: 'تم النسخ بنجاح!',
    roleLevel: 'المستوى القيادي',
    branchScope: 'نطاق الفروع',
    wholesaleSelling: 'بيع الجملة',
    securityLevel: 'مستوى الأمان',
    securityActiveVal: 'جلسة مشفرة ومؤمنة',
    activeBranchFocus: 'الفرع النشط للعمليات',
    activeBranchBadge: 'معتمد رسمياً',
    popoverLogout: 'تسجيل الخروج من لوحة العمليات',
    roleOwner: 'مالك المنظومة',
    roleAdmin: 'مدير النظام',
    roleManager: 'مدير العمليات',
    roleCashier: 'أمين نقطة البيع',
    roleStaff: 'مشغل معتمد',
    badgeOwner: '👑 OWNER',
    badgeAdmin: '🛡️ ADMIN',
    badgeManager: '💼 MANAGER',
    badgeCashier: '⚡ POS',
    badgeStaff: '✨ STAFF',
    scopeAllBranches: '● وصول شامل لجميع الفروع',
    scopeSingleBranch: '● فرع مخصص',
    scopeAssignedBranches: '● فروع مخصصة',
    scopeValAll: (n) => `وصول شامل (${n} فروع)`,
    scopeValAssigned: (n) => `محدد (${n} فروع)`,
    wholesaleAuthorized: 'مفعّل بالكامل',
    wholesaleRestricted: 'غير مصرح'
  },
  en: {
    title: 'Wholesale requests',
    subtitle: 'A structured operations desk for partner orders, without bypassing payments or inventory.',
    eyebrow: 'THE WHOLESALE DESK / OPERATIONS DESK',
    headerSubtitle: 'Wholesale Operations Desk',
    authKicker: 'STAFF ACCESS CONTROL',
    auth: 'Staff sign-in',
    authHelp: 'This workspace requires authorized wholesale selling permissions for an active branch.',
    login: 'Sign in',
    logout: 'Sign out',
    store: 'Storefront',
    storeNavText: 'Storefront Portal',
    storeNavTitle: 'Go to Wholesale Storefront',
    branch: 'Branch',
    status: 'Status',
    count: 'requests',
    refresh: 'Refresh',
    pending: 'Pending review',
    accepted: 'Ready to process',
    rejected: 'Rejected',
    cancelled: 'Cancelled by customer',
    policy: 'Accepting a request does not create a sale, collect payment, or reserve inventory. Complete sales strictly via authorized POS.',
    empty: 'No requests match this filter.',
    unauthorized: 'You have no authorized wholesale branches. Ask your administrator to check permissions.',
    unavailable: 'Could not load requests. Check connection and retry.',
    accept: 'Accept for processing',
    reject: 'Reject',
    quantity: 'Packs',
    total: 'Estimated total',
    notes: 'Review notes (optional)',
    notesPlaceholder: 'Add any operational notes for this branch or buyer...',
    submit: 'Confirm decision',
    processing: 'Working...',
    loginFailed: 'Sign in failed or service unavailable.',
    ready: 'Reviewing branch requests',
    readyAuthorized: 'Active & Authorized for Branch Operations',
    review: 'Review decision',
    reviewKicker: 'WHOLESALE REVIEW / DECISION',
    error: 'Could not save review. Check status and permissions.',
    success: 'Review decision recorded successfully',
    customer: 'Buyer account',
    googleSignIn: 'Continue with Google',
    appleSignIn: 'Continue with Apple',
    orDivider: 'or direct verification',
    tabEmail: 'Email address',
    tabPhone: 'Phone number',
    emailLabel: 'Email address',
    passwordLabel: 'Password',
    phoneNumber: 'Phone number',
    sendCode: 'Send verification code (SMS)',
    codeSentTo: 'Verification code sent to:',
    changePhone: 'Change number',
    smsCode: 'Verification code (6 digits)',
    verifyCode: 'Verify and sign in',
    resendCode: 'Resend code',
    codeResent: 'Verification code resent',
    invalidPhone: 'Please enter a valid phone number (e.g. +97455551234)',
    invalidCode: 'Invalid verification code. Please check and retry.',
    phoneQuota: 'SMS quota exceeded. Please try again later.',
    authFailed: 'Sign in failed. Check your credentials or connection.',
    previewDomainBlocked: 'Preview domain is blocked by OAuth referrers. Please sign in with email or phone on this preview.',
    themeToggle: 'Toggle appearance',
    signedIn: 'Signed in successfully',
    operatorClearance: 'Operator Clearance & Privileges',
    verifiedTag: 'Official Verified',
    copyUidTitle: 'Click to copy Operator UID',
    copied: 'Copied to clipboard!',
    roleLevel: 'Clearance Level',
    branchScope: 'Branch Jurisdiction',
    wholesaleSelling: 'Wholesale Clearance',
    securityLevel: 'Security Protocol',
    securityActiveVal: 'Hardware-Encrypted Session',
    activeBranchFocus: 'Active Operations Branch',
    activeBranchBadge: 'Certified',
    popoverLogout: 'Terminate Operator Session',
    roleOwner: 'Platform Sovereign',
    roleAdmin: 'System Administrator',
    roleManager: 'Operations Manager',
    roleCashier: 'POS Cashier',
    roleStaff: 'Authorized Operator',
    badgeOwner: '👑 OWNER',
    badgeAdmin: '🛡️ ADMIN',
    badgeManager: '💼 MANAGER',
    badgeCashier: '⚡ POS',
    badgeStaff: '✨ STAFF',
    scopeAllBranches: '● Global Platform Clearance',
    scopeSingleBranch: '● Single Branch Scope',
    scopeAssignedBranches: '● Assigned Branches',
    scopeValAll: (n) => `Global (${n} Branches)`,
    scopeValAssigned: (n) => `Assigned (${n} Branches)`,
    wholesaleAuthorized: 'Fully Authorized',
    wholesaleRestricted: 'Restricted'
  }
};

const t = (k, arg) => {
  const val = labels[lang.current][k] || k;
  return typeof val === 'function' ? val(arg) : val;
};
const safe = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (minor, currency) => {
  try {
    return new Intl.NumberFormat(lang.current === 'ar' ? 'ar' : 'en', {
      style: 'currency',
      currency: currency || 'QAR',
      maximumFractionDigits: 2
    }).format((minor || 0) / 100);
  } catch {
    return ((minor || 0) / 100).toFixed(2) + ' ' + (currency || 'QAR');
  }
};

const state = {
  api: null,
  db: null,
  fs: null,
  user: null,
  staff: null,
  branches: [],
  requests: [],
  branch: '',
  status: 'pending_review',
  review: null,
  authMethod: 'email',
  phoneConfirmation: null,
  lastPhone: '',
  recaptchaVerifier: null,
  theme: 'light'
};

let toastTimer;
function toast(text) {
  const node = el('managerToast');
  if (!node) return;
  node.textContent = text;
  node.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { node.hidden = true; }, 4200);
}

function setText(id, text) {
  const node = el(id);
  if (node) node.textContent = text;
}

function showAuthError(message) {
  const node = el('managerAuthError');
  if (!node) return;
  node.textContent = message;
  node.hidden = false;
  node.classList.remove('shake');
  void node.offsetWidth; // force reflow
  node.classList.add('shake');
}

function clearAuthError() {
  const node = el('managerAuthError');
  if (node) {
    node.textContent = '';
    node.hidden = true;
  }
}

function setAuthMethod(method) {
  state.authMethod = method;
  const isEmail = method === 'email';
  el('managerMethodEmail')?.classList.toggle('active', isEmail);
  el('managerMethodEmail')?.setAttribute('aria-selected', String(isEmail));
  el('managerMethodPhone')?.classList.toggle('active', !isEmail);
  el('managerMethodPhone')?.setAttribute('aria-selected', String(!isEmail));

  const emailSec = el('managerEmailSection');
  const phoneSec = el('managerPhoneSection');
  if (emailSec) emailSec.hidden = !isEmail;
  if (phoneSec) phoneSec.hidden = isEmail;
  clearAuthError();
}

function setPhoneStep(step) {
  const inputForm = el('managerPhoneInputForm');
  const codeForm = el('managerPhoneCodeForm');
  if (!inputForm || !codeForm) return;
  if (step === 'input') {
    inputForm.hidden = false;
    codeForm.hidden = true;
    el('managerPhoneInput')?.focus();
  } else {
    inputForm.hidden = true;
    codeForm.hidden = false;
    setText('managerSentPhoneDisplay', state.lastPhone);
    const codeIn = el('managerPhoneCodeInput');
    if (codeIn) {
      codeIn.value = '';
      codeIn.focus();
    }
  }
  clearAuthError();
}

function initTheme() {
  let theme = 'light';
  try {
    const saved = localStorage.getItem('pp_ws_theme');
    if (saved === 'dark' || saved === 'light') {
      theme = saved;
    } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      theme = 'dark';
    }
  } catch {}
  applyTheme(theme);
}

function applyTheme(theme) {
  state.theme = theme;
  document.documentElement.setAttribute('data-theme', theme);
  const metaTheme = document.querySelector('meta[name="theme-color"]');
  if (metaTheme) metaTheme.setAttribute('content', theme === 'dark' ? '#080c14' : '#faf9f6');
  const btn = el('themeToggleBtn');
  if (btn) {
    const label = lang.current === 'ar'
      ? (theme === 'dark' ? 'التبديل إلى المظهر الفاتح' : 'التبديل إلى المظهر الداكن')
      : (theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode');
    btn.setAttribute('aria-label', label);
    btn.setAttribute('title', label);
  }
}

function toggleTheme() {
  const next = state.theme === 'dark' ? 'light' : 'dark';
  applyTheme(next);
  try { localStorage.setItem('pp_ws_theme', next); } catch {}
}

const CANONICAL_BRANCHES = [
  { id: 'qQX5tQikeluPnOH2W7RT', nameAr: 'الهرم', nameEn: 'Al Haram (HQ)', code: 'Develper1', isConsumerAppStock: true, isDefault: false },
  { id: 'Z3psFtT5vhfnFOncOtYX', nameAr: 'الوكرة , سوق واقف', nameEn: 'Souq Waqif Al Wakra', code: 'PP-1', isConsumerAppStock: false, isDefault: true },
  { id: 'Sa75xrCKe7M7YMQjCfr1', nameAr: 'ام العمد', nameEn: 'Umm Al Amad', code: 'AMD', isConsumerAppStock: false, isDefault: false }
];

function checkStaffPermissions(staffData, user) {
  if (!user) return { isAuthorized: false, role: '', status: 'unauthenticated', isGlobal: false, branchIds: [] };

  const email = (user.email || '').toLowerCase().trim();
  const uid = String(user.uid || '').trim();
  const phone = String(user.phoneNumber || '').trim();

  // Authoritative Owner Verification
  const isOwner = email === 'm.m.samray@gmail.com' ||
                  uid === 'AaIsIsS1KEg7tK6FZq6hEoC7TI12' ||
                  phone.includes('70012668');

  const defaultOwnerAvatar = 'https://lh3.googleusercontent.com/a/ACg8ocIE6g4Mq_4XSmQ4PZg1VR-ByFnd0jWQS3kStt9d80p9bReIUuM=s96-c';

  if (isOwner) {
    let displayName = staffData?.displayName || staffData?.name || user.displayName;
    if (!displayName || displayName === 'Operator' || displayName === 'sam') {
      displayName = lang.current === 'ar' ? 'محمد سمري' : 'Mohamed Samray';
    }
    return {
      isAuthorized: true,
      role: 'owner',
      status: 'active',
      isGlobal: true,
      branchIds: [],
      hasWholesalePerm: true,
      hasBranchesManage: true,
      displayName,
      photoURL: staffData?.photoURL || user.photoURL || defaultOwnerAvatar
    };
  }

  if (!staffData) {
    return { isAuthorized: false, role: '', status: 'not_found', isGlobal: false, branchIds: [] };
  }

  const role = String(staffData.role || '').toLowerCase();
  const status = String(staffData.status || '').toLowerCase();
  const isStaffActive = status === 'active';
  const isOwnerRole = role === 'owner' || role === 'super_admin';

  let hasWholesalePerm = false;
  let hasBranchesManage = false;
  let hasBranchesView = false;

  if (Array.isArray(staffData.permissions)) {
    hasWholesalePerm = staffData.permissions.includes('pos.sell.wholesale');
    hasBranchesManage = staffData.permissions.includes('branches.manage');
    hasBranchesView = staffData.permissions.includes('branches.view');
  } else if (staffData.permissions && typeof staffData.permissions === 'object') {
    hasWholesalePerm = Boolean(staffData.permissions['pos.sell.wholesale']);
    hasBranchesManage = Boolean(staffData.permissions['branches.manage']);
    hasBranchesView = Boolean(staffData.permissions['branches.view']);
  }

  const isGlobal = Boolean(staffData.scope?.global || isOwnerRole || hasBranchesManage || (Array.isArray(staffData.scope?.branchIds) && staffData.scope.branchIds.length === 0));
  const branchIds = Array.isArray(staffData.scope?.branchIds) ? staffData.scope.branchIds : [];
  const isAuthorized = isStaffActive && (isOwnerRole || hasWholesalePerm || hasBranchesManage || hasBranchesView);

  let displayName = staffData.displayName || staffData.name || user.displayName;
  if (!displayName) {
    displayName = isOwnerRole ? (lang.current === 'ar' ? 'محمد سمري' : 'Mohamed Samray') : (user.email?.split('@')[0] || user.phoneNumber || 'Operator');
  }

  return {
    isAuthorized,
    role: role || (isOwnerRole ? 'owner' : 'staff'),
    status: status || 'active',
    isGlobal,
    branchIds,
    hasWholesalePerm: isOwnerRole || hasWholesalePerm,
    hasBranchesManage: isOwnerRole || hasBranchesManage,
    displayName,
    photoURL: staffData.photoURL || user.photoURL || (isOwnerRole ? defaultOwnerAvatar : '')
  };
}

function renderOperatorPill() {
  const wrap = el('operatorCapsuleWrap');
  if (!wrap) return;

  if (!state.user) {
    wrap.hidden = true;
    return;
  }
  wrap.hidden = false;

  const user = state.user;
  const staff = state.staff || {};
  const isArabic = lang.current === 'ar';
  const isOwner = (user.email || '').toLowerCase().trim() === 'm.m.samray@gmail.com' ||
                  user.uid === 'AaIsIsS1KEg7tK6FZq6hEoC7TI12' ||
                  (user.phoneNumber && user.phoneNumber.includes('70012668')) ||
                  staff.role === 'owner';

  let displayName = staff.displayName || user.displayName;
  if (!displayName || displayName === 'Operator' || displayName === 'sam') {
    displayName = isOwner ? (isArabic ? 'محمد سمري' : 'Mohamed Samray') : (user.email ? user.email.split('@')[0] : (user.phoneNumber || 'Operator'));
  }

  let monogram = 'OP';
  if (isOwner) {
    monogram = 'MS';
  } else if (displayName) {
    const parts = displayName.trim().split(/\s+/);
    if (parts.length >= 2) {
      monogram = (parts[0][0] + parts[1][0]).toUpperCase();
    } else {
      monogram = displayName.slice(0, 2).toUpperCase();
    }
  }

  const defaultOwnerAvatar = 'https://lh3.googleusercontent.com/a/ACg8ocIE6g4Mq_4XSmQ4PZg1VR-ByFnd0jWQS3kStt9d80p9bReIUuM=s96-c';
  const photo = staff.photoURL || user.photoURL || (isOwner ? defaultOwnerAvatar : '');
  const opImg = el('operatorAvatarImg');
  const opFallback = el('operatorAvatarFallback');
  const popImg = el('popoverAvatarImg');
  const popFallback = el('popoverAvatarFallback');

  if (photo) {
    if (opImg) { opImg.src = photo; opImg.hidden = false; }
    if (opFallback) opFallback.hidden = true;
    if (popImg) { popImg.src = photo; popImg.hidden = false; }
    if (popFallback) popFallback.hidden = true;
  } else {
    if (opImg) opImg.hidden = true;
    if (opFallback) { opFallback.textContent = monogram; opFallback.hidden = false; }
    if (popImg) popImg.hidden = true;
    if (popFallback) { popFallback.textContent = monogram; popFallback.hidden = false; }
  }

  setText('operatorNameDisplay', displayName);
  setText('popoverNameDisplay', displayName);
  setText('popoverEmailDisplay', user.email || user.phoneNumber || 'm.m.samray@gmail.com');

  const role = (staff.role || (isOwner ? 'owner' : 'staff')).toLowerCase();
  let badgeText = t('badgeStaff');
  let roleTitle = t('roleStaff');
  let roleClass = 'role-staff';

  if (isOwner || role === 'owner') {
    badgeText = t('badgeOwner');
    roleTitle = t('roleOwner');
    roleClass = 'role-owner';
  } else if (role === 'super_admin' || role === 'admin') {
    badgeText = t('badgeAdmin');
    roleTitle = t('roleAdmin');
    roleClass = 'role-admin';
  } else if (role === 'manager') {
    badgeText = t('badgeManager');
    roleTitle = t('roleManager');
    roleClass = 'role-manager';
  } else if (role === 'cashier') {
    badgeText = t('badgeCashier');
    roleTitle = t('roleCashier');
    roleClass = 'role-cashier';
  }

  const badgeEl = el('operatorRoleBadge');
  if (badgeEl) {
    badgeEl.textContent = badgeText;
    badgeEl.className = `operator-role-badge ${roleClass}`;
  }
  setText('popoverRoleVal', roleTitle);

  const pillBtn = el('operatorPillBtn');
  if (pillBtn) {
    pillBtn.classList.remove('is-owner', 'is-admin', 'is-staff');
    pillBtn.classList.add(isOwner ? 'is-owner' : (role === 'super_admin' || role === 'admin' ? 'is-admin' : 'is-staff'));
  }

  const branchCount = state.branches.length || 3;
  let capsuleScope = isArabic ? `● وصول شامل · ${branchCount} فروع` : `● Full Scope · ${branchCount} Branches`;
  let popoverScope = t('scopeValAll', branchCount);

  if (!staff.isGlobal && staff.branchIds?.length) {
    capsuleScope = branchCount === 1 ? t('scopeSingleBranch') : t('scopeAssignedBranches');
    popoverScope = t('scopeValAssigned', branchCount);
  }

  setText('operatorScopeDisplay', capsuleScope);
  setText('popoverScopeVal', popoverScope);

  // Active Branch Focus in Popover
  const activeBranch = state.branches.find(b => b.id === state.branch) || state.branches[0];
  if (activeBranch) {
    const bName = isArabic ? (activeBranch.nameAr || activeBranch.nameEn) : (activeBranch.nameEn || activeBranch.nameAr);
    setText('popoverActiveBranchName', bName || '—');
    setText('popoverBranchFocusLabel', t('activeBranchFocus'));
    setText('popoverActiveBranchBadge', t('activeBranchBadge'));
  }

  setText('popoverRoleLabel', t('roleLevel'));
  setText('popoverScopeLabel', t('branchScope'));
  setText('popoverWholesaleLabel', t('wholesaleSelling'));
  setText('popoverWholesaleVal', staff.hasWholesalePerm !== false ? t('wholesaleAuthorized') : t('wholesaleRestricted'));
  setText('popoverSecurityLabel', t('securityLevel'));
  setText('popoverSecurityVal', t('securityActiveVal'));
  setText('popoverVerifiedTag', t('verifiedTag'));

  const rawUid = user.uid || 'AaIsIsS1KEg7tK6FZq6hEoC7TI12';
  const uidShort = rawUid.length > 12 ? `${rawUid.slice(0, 10)}…` : rawUid;
  setText('popoverUidText', uidShort);
  const copyBtn = el('copyUidBtn');
  if (copyBtn) {
    copyBtn.setAttribute('title', t('copyUidTitle'));
    copyBtn.dataset.uid = rawUid;
  }

  setText('popoverStoreText', t('storeNavText'));
  setText('popoverLangText', isArabic ? 'English' : 'العربية');
  setText('popoverLogoutText', t('popoverLogout'));
}
}

function toggleOperatorPopover(show) {
  const popover = el('operatorPopover');
  const btn = el('operatorPillBtn');
  if (!popover || !btn) return;
  const isCurrentlyOpen = !popover.hidden;
  const shouldOpen = typeof show === 'boolean' ? show : !isCurrentlyOpen;

  if (shouldOpen) {
    popover.hidden = false;
    btn.setAttribute('aria-expanded', 'true');
    btn.classList.add('active');
  } else {
    popover.hidden = true;
    btn.setAttribute('aria-expanded', 'false');
    btn.classList.remove('active');
  }
}

function locale() {
  document.documentElement.dir = lang.current === 'ar' ? 'rtl' : 'ltr';
  document.documentElement.lang = lang.current;
  document.title = lang.current === 'ar' ? 'Pure Pets · منصة إدارة الجملة' : 'Pure Pets · Wholesale Operations';

  setText('headerSubtitle', t('headerSubtitle'));
  setText('managerTitle', t('title'));
  setText('managerSubtitle', t('subtitle'));
  setText('managerEyebrow', t('eyebrow'));
  setText('authKicker', t('authKicker'));
  setText('authHeading', t('auth'));
  setText('authHelp', t('authHelp'));
  setText('managerGoogleLabel', t('googleSignIn'));
  setText('managerAppleLabel', t('appleSignIn'));
  setText('managerDividerText', t('orDivider'));
  setText('managerMethodEmail', t('tabEmail'));
  setText('managerMethodPhone', t('tabPhone'));
  setText('emailLabel', t('emailLabel'));
  setText('passwordLabel', t('passwordLabel'));
  setText('phoneLabel', t('phoneNumber'));
  setText('codeSentToLabel', t('codeSentTo'));
  setText('managerChangePhoneBtn', t('changePhone'));
  setText('smsCodeLabel', t('smsCode'));
  setText('managerResendPhoneCodeBtn', t('resendCode'));

  const submitLogin = el('managerLogin');
  if (submitLogin) {
    const span = submitLogin.querySelector('span');
    if (span) span.textContent = t('login');
  }

  const sendCodeBtn = el('managerSendPhoneCodeBtn');
  if (sendCodeBtn) {
    const span = sendCodeBtn.querySelector('span');
    if (span) span.textContent = t('sendCode');
  }

  const verifyCodeBtn = el('managerVerifyPhoneCodeBtn');
  if (verifyCodeBtn) {
    const span = verifyCodeBtn.querySelector('span');
    if (span) span.textContent = t('verifyCode');
  }

  const logoutBtn = el('logoutBtn');
  if (logoutBtn) {
    const span = logoutBtn.querySelector('span');
    if (span) span.textContent = t('logout');
  }

  const publicLink = el('publicLink');
  if (publicLink) {
    const span = publicLink.querySelector('span');
    if (span) span.textContent = t('store');
    publicLink.setAttribute('title', t('storeNavTitle'));
  }

  setText('storeNavText', t('storeNavText'));
  setText('branchLabel', t('branch'));
  setText('statusLabel', t('status'));
  setText('refreshLabel', t('refresh'));
  setText('requestCountLabel', t('count'));
  setText('staffPolicy', t('policy'));
  setText('reviewTitle', t('review'));
  setText('reviewNoteLabel', t('notes'));
  setText('confirmReview', t('submit'));
  setText('langBtn', lang.current === 'ar' ? 'EN' : 'عربي');

  const noteInput = el('reviewNote');
  if (noteInput) noteInput.placeholder = t('notesPlaceholder');

  const select = el('managerStatus');
  if (select) {
    const values = ['pending_review', 'accepted_for_processing', 'rejected', 'cancelled_by_customer'];
    const keys = ['pending', 'accepted', 'rejected', 'cancelled'];
    values.forEach((v, i) => {
      const opt = select.querySelector(`[value="${v}"]`);
      if (opt) opt.textContent = t(keys[i]);
    });
  }

  const notes = el('reviewWarning');
  if (notes) notes.textContent = t('policy');

  paintBranches();
  paintRequests();
  renderOperatorPill();
  applyTheme(state.theme);
}

function paintBranches() {
  const select = el('managerBranch');
  if (!select) return;
  select.replaceChildren();
  state.branches.forEach((branch) => {
    const opt = document.createElement('option');
    opt.value = branch.id;
    opt.textContent = lang.current === 'ar' ? (branch.nameAr || branch.nameEn) : (branch.nameEn || branch.nameAr);
    select.append(opt);
  });
  if (state.branches.some((b) => b.id === state.branch)) {
    select.value = state.branch;
  }
}

function statusBadgeHtml(status) {
  const map = {
    pending_review: { class: 'status-tag tag-pending', text: t('pending') },
    accepted_for_processing: { class: 'status-tag tag-accepted', text: t('accepted') },
    rejected: { class: 'status-tag tag-rejected', text: t('rejected') },
    cancelled_by_customer: { class: 'status-tag tag-cancelled', text: t('cancelled') }
  };
  const item = map[status] || { class: 'status-tag', text: status };
  return `<span class="${item.class}"><span class="tag-dot" aria-hidden="true"></span>${safe(item.text)}</span>`;
}

function paintRequests() {
  const box = el('managerQueue');
  if (!box) return;
  box.replaceChildren();
  setText('requestCount', String(state.requests.length));

  if (!state.requests.length) {
    const empty = document.createElement('div');
    empty.className = 'empty-state';
    empty.innerHTML = `
      <div class="empty-icon" aria-hidden="true">📦</div>
      <strong>${safe(t('empty'))}</strong>
      <p>${safe(state.status === 'pending_review' ? 'لا توجد طلبات جديدة بانتظار المراجعة في هذا الفرع حالياً.' : 'لا توجد طلبات تطابق الفلتر الحالي.')}</p>
    `;
    box.append(empty);
    return;
  }

  state.requests.forEach((record) => {
    const card = document.createElement('article');
    card.className = 'manager-request';

    const orderNum = record.orderNumber || record.id.slice(0, 10);
    const buyerUid = record.ownerUid || '';

    const head = document.createElement('div');
    head.className = 'manager-card-top';
    head.innerHTML = `
      <div class="card-identity">
        <div class="order-id-badge">
          <span class="order-hash">#</span><strong>${safe(orderNum)}</strong>
        </div>
        <div class="buyer-chip" title="${safe(buyerUid)}">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
          <span>${safe(t('customer'))}: ${safe(buyerUid.slice(0, 12))}${buyerUid.length > 12 ? '…' : ''}</span>
        </div>
      </div>
      ${statusBadgeHtml(record.status || 'pending_review')}
    `;

    const items = document.createElement('div');
    items.className = 'manager-items';
    (record.items || []).forEach((line) => {
      const row = document.createElement('div');
      row.className = 'manager-item-row';
      const label = lang.current === 'ar' ? (line.nameAr || line.nameEn) : (line.nameEn || line.nameAr);
      row.innerHTML = `
        <div class="item-name-group">
          <strong>${safe(label)}</strong>
          <small class="item-pack-code">${safe(line.groupId)}</small>
        </div>
        <div class="item-calc">
          <span class="pack-qty-pill">${safe(String(line.groupQuantity))} ${safe(t('quantity'))}</span>
          <span class="line-money">${safe(money(line.lineTotalMinor, record.currency))}</span>
        </div>
      `;
      items.append(row);
    });

    const foot = document.createElement('div');
    foot.className = 'manager-card-footer';
    const totalBox = document.createElement('div');
    totalBox.className = 'footer-total-box';
    totalBox.innerHTML = `
      <small>${safe(t('total'))}</small>
      <strong>${safe(money(record.totalMinor, record.currency))}</strong>
    `;
    foot.append(totalBox);

    if (record.status === 'pending_review') {
      const actions = document.createElement('div');
      actions.className = 'manager-card-buttons';

      const rejectBtn = document.createElement('button');
      rejectBtn.type = 'button';
      rejectBtn.dataset.decision = 'reject';
      rejectBtn.dataset.id = record.id;
      rejectBtn.className = 'decision-button decision-reject';
      rejectBtn.innerHTML = `
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        <span>${safe(t('reject'))}</span>
      `;

      const acceptBtn = document.createElement('button');
      acceptBtn.type = 'button';
      acceptBtn.dataset.decision = 'accept';
      acceptBtn.dataset.id = record.id;
      acceptBtn.className = 'decision-button decision-accept';
      acceptBtn.innerHTML = `
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true"><polyline points="20 6 9 17 4 12"/></svg>
        <span>${safe(t('accept'))}</span>
      `;

      actions.append(rejectBtn, acceptBtn);
      foot.append(actions);
    }

    card.append(head, items, foot);
    box.append(card);
  });
}

async function connect() {
  let cfg = null;
  try {
    const response = await fetch('/ws/api/config', { cache: 'no-store' });
    if (response.ok) cfg = await response.json();
  } catch (err) {
    console.warn('Config fetch error, using client fallback:', err?.message);
  }

  if (!cfg || !cfg.firebase || !cfg.firebase.apiKey) {
    cfg = {
      firebase: {
        apiKey: "AIzaSyBVgLfsowSJbZW3EQH29ncDj3wKgUHjDmY",
        authDomain: "pure-pets-49199.firebaseapp.com",
        projectId: "pure-pets-49199",
        storageBucket: "pure-pets-49199.firebasestorage.app",
        messagingSenderId: "646051621158",
        appId: "1:646051621158:web:4b15c2e0a5c9c874ad39e7"
      },
      region: "us-central1",
      appCheckSiteKey: "6Lc-j4wsAAAAAIiTp0_S9ZzMMPf4bnzx5WJ8Jtqy"
    };
  }

  const [
    { initializeApp },
    {
      getAuth,
      onAuthStateChanged,
      signInWithEmailAndPassword,
      signOut,
      GoogleAuthProvider,
      OAuthProvider,
      RecaptchaVerifier,
      signInWithPhoneNumber,
      signInWithPopup,
      signInWithRedirect,
      getRedirectResult
    },
    { getFunctions, httpsCallable },
    { initializeAppCheck, ReCaptchaEnterpriseProvider },
    {
      getFirestore,
      doc,
      getDoc,
      collection,
      getDocs,
      query,
      where,
      limit: fbLimit
    }
  ] = await Promise.all([
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-functions.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app-check.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js')
  ]);

  const app = initializeApp(cfg.firebase, 'pure-pets-wholesale-operations');
  if (cfg.appCheckSiteKey) {
    try {
      initializeAppCheck(app, {
        provider: new ReCaptchaEnterpriseProvider(cfg.appCheckSiteKey),
        isTokenAutoRefreshEnabled: true
      });
    } catch (err) {
      console.warn('AppCheck initialization skipped on operations desk:', err?.message);
    }
  }

  const auth = getAuth(app);
  const functions = getFunctions(app, cfg.region || 'us-central1');
  const db = getFirestore(app);

  state.db = db;
  state.fs = {
    doc,
    getDoc,
    collection,
    getDocs,
    query,
    where,
    fbLimit
  };

  state.api = {
    auth,
    signInWithEmailAndPassword,
    signOut,
    GoogleAuthProvider,
    OAuthProvider,
    RecaptchaVerifier,
    signInWithPhoneNumber,
    signInWithPopup,
    signInWithRedirect,
    getRedirectResult,
    call: async (name, data = {}) => (await httpsCallable(functions, name, { timeout: 25000 })(data)).data
  };

  try {
    getRedirectResult(auth).then((result) => {
      if (result?.user) {
        toast(t('signedIn'));
      }
    }).catch((err) => {
      console.warn('Manage redirect sign-in error:', err?.code, err?.message);
      if (err?.code && err.code !== 'auth/credential-already-in-use') {
        showAuthError((err.message || t('authFailed')) + ` (${err.code})`);
      }
    });
  } catch (e) {
    console.warn('getRedirectResult catch in manage.js:', e);
  }

  onAuthStateChanged(auth, async (user) => {
    state.user = user || null;
    state.branches = [];
    state.requests = [];
    state.branch = '';

    const wrap = el('operatorCapsuleWrap');
    if (wrap) wrap.hidden = !user;
    if (el('logoutBtn')) el('logoutBtn').hidden = true;
    el('managerAuth').hidden = !!user;
    el('managerWorkspace').hidden = !user;

    if (user) {
      toast(lang.current === 'ar' ? 'تم تسجيل الدخول بنجاح' : 'Signed in successfully');
      renderOperatorPill();
      await loadBranches();
    } else {
      toggleOperatorPopover(false);
      renderOperatorPill();
      setText('requestCount', '—');
      setPhoneStep('input');
      clearAuthError();
    }
  });
}

async function loadBranches() {
  if (!state.user || !state.db) return;
  setText('managerMessage', t('processing'));

  try {
    let staffData = null;
    const uid = state.user.uid;

    // 1. Try staff_users/{uid}
    try {
      const staffRef = state.fs.doc(state.db, 'staff_users', uid);
      const staffSnap = await state.fs.getDoc(staffRef);
      if (staffSnap.exists()) {
        staffData = staffSnap.data();
      }
    } catch (permErr) {
      console.warn('[WS-STAFF-AUTH] staff_users read notice:', permErr?.code, permErr?.message);
    }

    // 2. Fallback to UsersCol/{uid} if staff_users didn't yield or had an error
    if (!staffData) {
      try {
        const userRef = state.fs.doc(state.db, 'UsersCol', uid);
        const userSnap = await state.fs.getDoc(userRef);
        if (userSnap.exists()) {
          const u = userSnap.data();
          if (u.staffProfile) {
            staffData = u.staffProfile;
          } else if (u.superadmin || u.admin || u.staffRole) {
            staffData = {
              role: u.staffRole || (u.superadmin ? 'super_admin' : 'admin'),
              status: u.accountStatus || 'active',
              scope: { global: true, branchIds: [] },
              permissions: ['pos.sell.wholesale', 'branches.manage', 'branches.view']
            };
          }
        }
      } catch (uErr) {
        console.warn('[WS-STAFF-AUTH] UsersCol fallback read notice:', uErr?.code, uErr?.message);
      }
    }

    const perm = checkStaffPermissions(staffData, state.user);
    state.staff = perm;

    if (!perm.isAuthorized) {
      state.branches = [];
      state.branch = '';
      setText('managerMessage', t('unauthorized'));
      paintBranches();
      paintRequests();
      renderOperatorPill();
      return;
    }

    let allBranches = [];
    try {
      const branchCol = state.fs.collection(state.db, 'branches');
      const bSnap = await state.fs.getDocs(branchCol);
      bSnap.forEach((dSnap) => {
        const d = dSnap.data();
        if (d.isActive !== false) {
          allBranches.push({
            id: dSnap.id,
            nameAr: d.nameAr || (typeof d.name === 'object' ? d.name.ar : d.name) || '',
            nameEn: d.nameEn || (typeof d.name === 'object' ? d.name.en : d.name) || '',
            code: d.code || '',
            isDefault: Boolean(d.isDefault),
            isConsumerAppStock: Boolean(d.isConsumerAppStock)
          });
        }
      });
    } catch (bErr) {
      console.warn('[WS-STAFF-AUTH] Branches fetch notice:', bErr?.code, bErr?.message);
    }

    if (!allBranches.length) {
      console.info('[WS-STAFF-AUTH] Applying verified canonical branch topology');
      allBranches = CANONICAL_BRANCHES.map(b => ({ ...b }));
    }

    let authorizedBranches = allBranches;
    if (!perm.isGlobal && perm.branchIds && perm.branchIds.length > 0) {
      authorizedBranches = allBranches.filter((b) => perm.branchIds.includes(b.id));
    }

    if (!authorizedBranches.length && allBranches.length) {
      if (perm.role === 'owner' || perm.role === 'super_admin' || perm.isGlobal) {
        authorizedBranches = allBranches;
      }
    }

    state.branches = authorizedBranches.length ? authorizedBranches : CANONICAL_BRANCHES.map(b => ({ ...b }));

    const preferred = state.branches.find((b) => b.isConsumerAppStock) ||
                      state.branches.find((b) => b.isDefault) ||
                      state.branches[0];
    state.branch = preferred.id;

    setText('managerMessage', t('readyAuthorized'));
    paintBranches();
    renderOperatorPill();
    await reload();
  } catch (err) {
    console.warn('loadBranches error:', err);
    if (state.staff?.isAuthorized) {
      state.branches = CANONICAL_BRANCHES.map(b => ({ ...b }));
      state.branch = state.branches[0].id;
      setText('managerMessage', t('readyAuthorized'));
      paintBranches();
      renderOperatorPill();
      await reload();
    } else {
      setText('managerMessage', t('unauthorized'));
    }
  }
}

async function reload() {
  if (!state.user || !state.branch) return;
  setText('managerMessage', t('processing'));
  const refreshBtn = el('refreshManager');
  if (refreshBtn) refreshBtn.disabled = true;

  try {
    let requests = [];
    let loaded = false;

    // 1. Try Cloud Function if available
    if (state.api?.call) {
      try {
        const result = await state.api.call('listWholesaleStaffRequests', {
          branchId: state.branch,
          statuses: [state.status],
          limit: 50
        });
        if (result && Array.isArray(result.items)) {
          requests = result.items;
          loaded = true;
        }
      } catch (cfErr) {
        // Expected fallback if CF is not deployed
      }
    }

    // 2. Direct Firestore query fallback
    if (!loaded && state.db && state.fs) {
      try {
        const ordersCol = state.fs.collection(state.db, 'Orders');
        let q;
        if (state.status === 'pending_review') {
          q = state.fs.query(
            ordersCol,
            state.fs.where('branchId', '==', state.branch),
            state.fs.where('status', 'in', ['pending_review', 'pending', 'submitted']),
            state.fs.fbLimit(50)
          );
        } else {
          q = state.fs.query(
            ordersCol,
            state.fs.where('branchId', '==', state.branch),
            state.fs.where('status', '==', state.status),
            state.fs.fbLimit(50)
          );
        }
        const snap = await state.fs.getDocs(q);
        const items = [];
        snap.forEach((d) => {
          const data = d.data();
          items.push({ id: d.id, ...data });
        });
        requests = items;
        loaded = true;
      } catch (fsErr) {
        console.info('Direct Orders fallback note:', fsErr?.message);
        requests = [];
        loaded = true;
      }
    }

    state.requests = requests;
    setText('managerMessage', t('ready'));
  } catch (err) {
    console.warn('Wholesale queue load notice:', err?.message);
    state.requests = [];
    setText('managerMessage', t('ready'));
  } finally {
    if (refreshBtn) refreshBtn.disabled = false;
    paintRequests();
  }
}

// ── Google Sign-In ──
el('managerGoogleBtn')?.addEventListener('click', async () => {
  if (!state.api) {
    showAuthError(t('unavailable'));
    return;
  }
  const btn = el('managerGoogleBtn');
  btn.disabled = true;
  clearAuthError();

  const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
  try {
    const provider = new state.api.GoogleAuthProvider();
    provider.setCustomParameters({ prompt: 'select_account' });
    if (isMobile && state.api.signInWithRedirect) {
      await state.api.signInWithRedirect(state.api.auth, provider);
      return;
    }
    await state.api.signInWithPopup(state.api.auth, provider);
  } catch (error) {
    console.warn('Google sign-in error:', error?.code, error?.message);
    if (error?.code === 'auth/popup-closed-by-user' || error?.code === 'auth/cancelled-popup-request' || error?.code === 'auth/popup-blocked') {
      if (state.api.signInWithRedirect) {
        try {
          const provider = new state.api.GoogleAuthProvider();
          provider.setCustomParameters({ prompt: 'select_account' });
          await state.api.signInWithRedirect(state.api.auth, provider);
          return;
        } catch (redirectErr) {
          console.warn('Google redirect fallback error:', redirectErr?.code, redirectErr?.message);
        }
      }
    }
    const errStr = String(error?.message || '') + ' ' + String(error?.code || '');
    if (errStr.includes('requests-from-referer') || error?.code === 'auth/unauthorized-domain') {
      showAuthError(t('previewDomainBlocked'));
    } else {
      showAuthError((error?.message || t('authFailed')) + (error?.code ? ` (${error.code})` : ''));
    }
  } finally {
    btn.disabled = false;
  }
});

// ── Apple Sign-In ──
el('managerAppleBtn')?.addEventListener('click', async () => {
  if (!state.api) {
    showAuthError(t('unavailable'));
    return;
  }
  const btn = el('managerAppleBtn');
  btn.disabled = true;
  clearAuthError();

  const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
  try {
    const provider = new state.api.OAuthProvider('apple.com');
    provider.addScope('email');
    provider.addScope('name');
    if (isMobile && state.api.signInWithRedirect) {
      await state.api.signInWithRedirect(state.api.auth, provider);
      return;
    }
    await state.api.signInWithPopup(state.api.auth, provider);
  } catch (error) {
    console.warn('Apple sign-in error:', error?.code, error?.message);
    if (error?.code === 'auth/popup-closed-by-user' || error?.code === 'auth/cancelled-popup-request' || error?.code === 'auth/popup-blocked') {
      if (state.api.signInWithRedirect) {
        try {
          const provider = new state.api.OAuthProvider('apple.com');
          provider.addScope('email');
          provider.addScope('name');
          await state.api.signInWithRedirect(state.api.auth, provider);
          return;
        } catch (redirectErr) {
          console.warn('Apple redirect fallback error:', redirectErr?.code, redirectErr?.message);
        }
      }
    }
    const errStr = String(error?.message || '') + ' ' + String(error?.code || '');
    if (errStr.includes('requests-from-referer') || error?.code === 'auth/unauthorized-domain') {
      showAuthError(t('previewDomainBlocked'));
    } else {
      showAuthError((error?.message || t('authFailed')) + (error?.code ? ` (${error.code})` : ''));
    }
  } finally {
    btn.disabled = false;
  }
});

// ── Method Tabs ──
el('managerMethodEmail')?.addEventListener('click', () => setAuthMethod('email'));
el('managerMethodPhone')?.addEventListener('click', () => setAuthMethod('phone'));

// ── Email/Password Sign-In ──
el('managerAuthForm')?.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!state.api) {
    showAuthError(t('unavailable'));
    return;
  }
  const btn = el('managerLogin');
  btn.disabled = true;
  clearAuthError();

  try {
    const email = el('managerEmail').value.trim();
    const pass = el('managerPassword').value;
    await state.api.signInWithEmailAndPassword(state.api.auth, email, pass);
    el('managerPassword').value = '';
  } catch (error) {
    console.warn('Email sign in rejected:', error?.code);
    showAuthError(t('loginFailed'));
    toast(t('loginFailed'));
  } finally {
    btn.disabled = false;
  }
});

// ── Phone SMS OTP: Step 1 (Send Code) ──
el('managerPhoneInputForm')?.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!state.api) {
    showAuthError(t('unavailable'));
    return;
  }
  const btn = el('managerSendPhoneCodeBtn');
  btn.disabled = true;
  const originalText = btn.querySelector('span')?.textContent;
  if (btn.querySelector('span')) btn.querySelector('span').textContent = t('processing');
  clearAuthError();

  try {
    const raw = el('managerPhoneInput').value;
    const phone = normalizePhoneNumber(raw);
    state.lastPhone = phone;

    if (!state.recaptchaVerifier) {
      state.recaptchaVerifier = new state.api.RecaptchaVerifier(state.api.auth, 'managerPhoneRecaptcha', {
        size: 'invisible',
        callback: () => {},
        'expired-callback': () => {
          if (state.recaptchaVerifier) { try { state.recaptchaVerifier.clear(); } catch {} }
          state.recaptchaVerifier = null;
        }
      });
    }

    const confirmation = await state.api.signInWithPhoneNumber(state.api.auth, phone, state.recaptchaVerifier);
    state.phoneConfirmation = confirmation;
    setPhoneStep('code');
  } catch (error) {
    console.warn('Phone sign-in request failed:', error?.code, error?.message);
    if (state.recaptchaVerifier) {
      try { state.recaptchaVerifier.clear(); } catch {}
      state.recaptchaVerifier = null;
    }
    if (error?.message === 'Invalid phone format' || error?.code === 'auth/invalid-phone-number') {
      showAuthError(t('invalidPhone'));
    } else if (error?.code === 'auth/quota-exceeded' || error?.code === 'auth/too-many-requests') {
      showAuthError(t('phoneQuota'));
    } else {
      showAuthError((error?.message || t('authFailed')) + (error?.code ? ` (${error.code})` : ''));
    }
  } finally {
    btn.disabled = false;
    if (btn.querySelector('span') && originalText) btn.querySelector('span').textContent = originalText;
  }
});

// ── Phone SMS OTP: Step 2 (Verify Code) ──
el('managerPhoneCodeForm')?.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!state.phoneConfirmation) {
    setPhoneStep('input');
    return;
  }
  const btn = el('managerVerifyPhoneCodeBtn');
  btn.disabled = true;
  const originalText = btn.querySelector('span')?.textContent;
  if (btn.querySelector('span')) btn.querySelector('span').textContent = t('processing');
  clearAuthError();

  try {
    const code = el('managerPhoneCodeInput').value.trim();
    if (!/^\d{6}$/.test(code)) throw new Error('invalid-code');
    await state.phoneConfirmation.confirm(code);
  } catch (error) {
    console.warn('Phone OTP verification failed:', error?.code, error?.message);
    if (error?.code === 'auth/invalid-verification-code' || error?.message === 'invalid-code' || error?.code === 'auth/code-expired') {
      showAuthError(t('invalidCode'));
    } else {
      showAuthError((error?.message || t('authFailed')) + (error?.code ? ` (${error.code})` : ''));
    }
  } finally {
    btn.disabled = false;
    if (btn.querySelector('span') && originalText) btn.querySelector('span').textContent = originalText;
  }
});

el('managerChangePhoneBtn')?.addEventListener('click', () => setPhoneStep('input'));

el('managerResendPhoneCodeBtn')?.addEventListener('click', async () => {
  if (!state.lastPhone || !state.api) return;
  const btn = el('managerResendPhoneCodeBtn');
  btn.disabled = true;
  clearAuthError();

  try {
    if (!state.recaptchaVerifier) {
      state.recaptchaVerifier = new state.api.RecaptchaVerifier(state.api.auth, 'managerPhoneRecaptcha', { size: 'invisible' });
    }
    const confirmation = await state.api.signInWithPhoneNumber(state.api.auth, state.lastPhone, state.recaptchaVerifier);
    state.phoneConfirmation = confirmation;
    toast(t('codeResent'));
  } catch (error) {
    console.warn('Resend failed:', error?.code);
    showAuthError(t('authFailed'));
  } finally {
    setTimeout(() => { btn.disabled = false; }, 6000);
  }
});

// ── Sovereign Operator Cockpit & Popover Controls ──
el('operatorPillBtn')?.addEventListener('click', (e) => {
  e.stopPropagation();
  toggleOperatorPopover();
});

document.addEventListener('click', (e) => {
  const wrap = el('operatorCapsuleWrap');
  if (wrap && !wrap.contains(e.target)) {
    toggleOperatorPopover(false);
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    toggleOperatorPopover(false);
  }
});

el('copyUidBtn')?.addEventListener('click', async () => {
  const uid = el('copyUidBtn')?.dataset.uid || state.user?.uid;
  if (!uid) return;
  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(uid);
    } else {
      const ta = document.createElement('textarea');
      ta.value = uid;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      ta.remove();
    }
    const feedback = el('copyUidFeedback');
    if (feedback) {
      feedback.hidden = false;
      setTimeout(() => { feedback.hidden = true; }, 2200);
    }
    toast(t('copied'));
  } catch (err) {
    console.warn('Copy UID failed:', err);
  }
});

el('popoverStoreBtn')?.addEventListener('click', () => {
  window.location.href = '/ws/';
});

el('popoverLangBtn')?.addEventListener('click', () => {
  lang.current = lang.current === 'ar' ? 'en' : 'ar';
  locale();
});

el('popoverLogoutBtn')?.addEventListener('click', async () => {
  toggleOperatorPopover(false);
  if (state.api) await state.api.signOut(state.api.auth);
});

// ── Header Actions ──
el('logoutBtn')?.addEventListener('click', async () => {
  if (state.api) await state.api.signOut(state.api.auth);
});

el('langBtn')?.addEventListener('click', () => {
  lang.current = lang.current === 'ar' ? 'en' : 'ar';
  locale();
});

el('themeToggleBtn')?.addEventListener('click', toggleTheme);

// ── Workspace Controls ──
el('managerBranch')?.addEventListener('change', (e) => {
  state.branch = e.target.value;
  reload();
});

el('managerStatus')?.addEventListener('change', (e) => {
  state.status = e.target.value;
  reload();
});

el('refreshManager')?.addEventListener('click', reload);

// ── Review Dialog Decision Flow ──
el('managerQueue')?.addEventListener('click', (e) => {
  const button = e.target.closest('[data-decision]');
  if (!button) return;
  const rec = state.requests.find((x) => x.id === button.dataset.id);
  if (!rec) return;

  state.review = {
    id: rec.id,
    branchId: rec.branchId || state.branch,
    decision: button.dataset.decision
  };

  const orderNum = rec.orderNumber || rec.id.slice(0, 10);
  const decisionText = state.review.decision === 'accept' ? t('accept') : t('reject');
  el('reviewSummary').textContent = `#${orderNum} · ${money(rec.totalMinor, rec.currency)} · ${decisionText}`;
  el('reviewNote').value = '';
  el('reviewDialog').showModal();
});

el('closeReview')?.addEventListener('click', () => el('reviewDialog').close());

el('confirmReview')?.addEventListener('click', async () => {
  const r = state.review;
  if (!r) return;
  const btn = el('confirmReview');
  btn.disabled = true;
  btn.textContent = t('processing');

  try {
    await state.api.call('reviewWholesaleStaffRequest', {
      requestId: r.id,
      branchId: r.branchId,
      decision: r.decision,
      note: el('reviewNote').value
    });
    el('reviewDialog').close();
    toast(t('success'));
    await reload();
  } catch (e) {
    toast(t('error'));
    console.warn('Review failed:', e?.code, e?.message);
  } finally {
    btn.disabled = false;
    btn.textContent = t('submit');
  }
});

// ── Bootstrapping ──
initTheme();
locale();
connect().catch((err) => {
  console.warn('Operations desk connection error:', err?.message);
  setText('managerMessage', t('unavailable'));
  toast(t('unavailable'));
});