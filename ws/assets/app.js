
import { protectedIntent, mergeCart, normalizeCatalogItem, normalizePhoneNumber } from './state.js';

const $ = (id) => document.getElementById(id);
const t = {
  ar: {
    top:'بوابة الأعمال من Pure Pets',wholesale:'تجربة مخصصة لطلبات الجملة',navCatalog:'المنتجات',navOrders:'طلباتي',
    cart:'السلة',login:'دخول / تسجيل',logout:'تسجيل الخروج',eyebrow:'PURE PETS / BUSINESS',heroOne:'رعاية لهم.',heroTwo:'ونموّ لتجارتك.',
    heroDesc:'منتجات مختارة بعناية، وحدات بيع واضحة، وتجربة طلب تناسب طموح تجارتك.',explore:'اكتشف المنتجات',
    guestHint:'تصفح بحرية. سجّل دخولك فقط عند اتخاذ إجراء.',collection:'THE COLLECTION / المجموعة',catalogHeading:'اكتشف مجموعتنا',
    catalogHint:'منتجات الجملة المعتمدة فقط، تباع بالكرتون والعبوات (غير متاح بالقطعة).',products:'منتج',search:'ابحث عن المنتجات...',
    sortFeatured:'الترتيب الافتراضي',sortLow:'الأقل سعراً',sortHigh:'الأعلى سعراً',loadMore:'عرض المزيد',
    promiseOne:'كراتين وعبوات جملة واضحة',promiseTwo:'أسعار جملة معتمدة',promiseThree:'طلبات مرتبطة بحسابك',footerCopy:'كل ما يحتاجه مشروعك، من مكان واحد.',
    advantageKicker:'ميثاق التوريد المعتمد · PRESTIGE B2B',advantageTitle:'معايير توريد صُممت لنمو تجارتك',advantageSubtitle:'منظومة لوجستية وتجارية متكاملة تضمن لمتجرك أو عيادتك أعلى درجات الموثوقية وهوامش الربح.',
    promiseOneBadge:'عبوات وكراتين فقط',promiseOneDesc:'توريد تجاري مباشر بالكرتون والشدّات لضمان أفضل هوامش ربحية وتلبية احتياجات المتاجر والعيادات البيطرية دون وسيط.',
    promiseOneBullet1:'أحجام توريد اقتصادية واضحة',promiseOneBullet2:'غير متاح بالقطعة (حماية لهوامش الموزعين)',
    promiseTwoBadge:'تسعير جملة فوري',promiseTwoDesc:'تسعير فوري وشفاف مع فواتير تجارية رقمية وضريبية معتمدة لكافة الأصناف بدون رسوم خفية.',
    promiseTwoBullet1:'أسعار تنافسية مبنية على حجم الطلب',promiseTwoBullet2:'فواتير رسمية قابلة للتحميل الفوري',
    promiseThreeBadge:'ربط وتجهيز فوري',promiseThreeDesc:'متابعة حية لحالة الشحنات، سجل الفواتير السابقة، وأولوية التجهيز المباشر من مستودع الهرم المعتمد.',
    promiseThreeBullet1:'أولوية الصرف والتجهيز السريع',promiseThreeBullet2:'تعيين تلقائي لمستودع الهرم المخصص',
    telemetryLiveStatus:'شبكة الجملة تعمل بكفاءة حية',telemetryHubLabel:'مستودع التوزيع المركزي: الهرم (مخزون تطبيق Pure Pets المعتمد)',telemetryConcierge:'المساعد التجاري (واتساب)',
    footerBrandDesc:'كل ما يحتاجه مشروعك، من مكان واحد. المنظومة القطرية المتخصصة في تزويد المتاجر، العيادات البيطرية، والمربين المعتمدين بأجود المنتجات.',
    footerColCatalog:'الكتالوج والتوريد',footerLinkAll:'كافة منتجات الجملة',footerLinkPacks:'كراتين ومستلزمات الغذاء',footerLinkCare:'العناية والرعاية البيطرية',footerLinkNew:'الأصناف المضافة حديثاً',
    footerColBuyer:'مساحة المشتري',footerLinkCart:'سلة المشتريات والطلبات',footerLinkOrders:'متابعة الطلبات والفواتير',footerLinkAccount:'تسجيل دخول المنشآت',footerLinkStaff:'لوحة إدارة العمليات (Staff)',
    footerColReach:'التغطية والدعم',footerReachDesc:'شحن تجاري سريع يغطي كافة بلديات دولة قطر:',footerSupportPhone:'هاتف الدعم: +974 5999 7720',
    footerQatarVerified:'منصة مرخصة وموثقة · دولة قطر',footerVetInspected:'فحص بيطري وتوريد معتمد',
    footerLegalCopy:'© 2026 Pure Pets Wholesale Platform W.L.L. جميع الحقوق محفوظة في دولة قطر.',
    footerLegalStewardship:'تخضع كافة المعاملات التجارية ومعايير التوريد للأنظمة واللوائح المعتمدة في دولة قطر.',
    footerAscend:'للأعلى',doha:'الدوحة',alrayyan:'الريان',alwakrah:'الوكرة',alkhor:'الخور',lusail:'لوسيل',alshamal:'الشمال',
    workspace:'مساحة مشتري الجملة',authTitle:'أهلاً بك في عالم الجملة',authIntro:'أكمل تسجيل الدخول للمتابعة من حيث توقفت.',
    loginTab:'تسجيل الدخول',registerTab:'إنشاء حساب',email:'البريد الإلكتروني',password:'كلمة المرور',continue:'متابعة',
    all:'الكل',emptyTitle:'لا توجد منتجات مطابقة',emptyText:'غيّر كلمة البحث أو التصفية وحاول مرة أخرى.',
    unavailableTitle:'المتجر غير جاهز حالياً',unavailableText:'تعذر تحميل كتالوج الجملة. قد تكون خدمة المنتجات قيد الإعداد. حاول لاحقاً.',
    retry:'إعادة المحاولة',starting:'يتم تحميل المجموعة...',startingAuth:'التحقق من الحساب...',from:'يبدأ من',perPack:'للعبوة',
    soldOut:'غير متاح الآن',add:'أضف للسلة',save:'حفظ لوقت لاحق',details:'تفاصيل المنتج',selectPack:'وحدة البيع',quantity:'عدد العبوات',
    noAccount:'يرجى تسجيل الدخول أولاً',cartEmpty:'السلة فارغة',savedEmpty:'لم تحفظ أي منتجات بعد',
    ordersEmpty:'لا توجد طلبات جملة حتى الآن',cartHeading:'سلة الجملة',savedHeading:'المحفوظات',ordersHeading:'طلباتي',
    remove:'إزالة',requestOrder:'إرسال طلب جملة',total:'الإجمالي التقديري',branch:'فرع الاستلام / التنفيذ',
    branchMissing:'لا توجد فروع منشورة للطلب حالياً. يمكن تصفح المنتجات والحفظ، لكن إرسال الطلبات متوقف مؤقتاً.',
    draftNote:'الطلب لا يعتبر مدفوعاً أو مؤكداً إلا بعد مراجعة فريق Pure Pets. الأسعار والمخزون يعاد التحقق منهما بالخادم.',
    signedIn:'تم تسجيل الدخول بنجاح',added:'تمت الإضافة إلى السلة',saved:'تم حفظ المنتج',requestSent:'تم إرسال طلب الجملة للمراجعة',
    saveFailed:'تعذر حفظ البيانات، حاول مرة أخرى',removed:'تمت الإزالة',comingSoon:'المنتج غير متاح حالياً',
    authFailed:'تعذر تسجيل الدخول. تحقق من بياناتك أو إعدادات التسجيل.',sessionFailed:'تعذر التحقق من الحساب.',
    processing:'يتم التنفيذ...',requestFailed:'تعذر إرسال الطلب. تحقق من الكمية أو الأسعار وأعد المحاولة.',
    noProducts:'لا تتوفر منتجات جملة منشورة حالياً.',signupConfirm:'أنشئ حسابك لتتابع الشراء.',welcome:'حسابي',open:'فتح',status:'الحالة',
    units:'قطعة',verified:'سعر الجملة',noBranch:'اختر الفرع',cancelRequest:'إلغاء الطلب',cancelConfirm:'هل تريد إلغاء طلب الجملة المعلق؟',cancelSuccess:'تم إلغاء الطلب',increase:'زيادة الكمية',decrease:'تقليل الكمية',
    availableStock:'المتوفر بالمخزن',outOfStock:'نفد من المخزن',inCart:'في السلة',packsInCart:'عبوة في السلة',packs:'عبوة',alreadyInCart:'مضاف في السلة حالياً',
    fulfillmentBranch:'فرع التنفيذ (المعتمد لتطبيق الآيفون)',assignedBranchLabel:'فرع الصرف والتنفيذ',consumerAppBranchNote:'تم تحديد الفرع تلقائياً وفقاً لمخزون تطبيق Pure Pets للعملاء (الهرم)',
    googleSignIn:'المتابعة باستخدام Google',appleSignIn:'المتابعة باستخدام Apple',orDivider:'أو',tabEmail:'البريد الإلكتروني',tabPhone:'رقم الهاتف',
    phoneNumber:'رقم الهاتف',sendCode:'إرسال رمز التحقق (SMS)',codeSentTo:'تم إرسال رمز التحقق إلى:',
    changePhone:'تغيير الرقم',smsCode:'رمز التحقق (6 أرقام)',verifyCode:'تأكيد الرمز والدخول',
    resendCode:'إعادة إرسال الرمز',codeResent:'تمت إعادة إرسال رمز التحقق',invalidPhone:'يرجى إدخال رقم هاتف صحيح (مثال: +97455551234)',
    invalidCode:'رمز التحقق غير صحيح، يرجى التأكد وإعادة المحاولة.',phoneQuota:'تم تجاوز الحد المسموح لإرسال الرسائل، حاول لاحقاً.',
    resetFilters:'إعادة ضبط الفلاتر',activeFilters:'التصفيات الحالية:',allCount:'منتج جملة',
    heroBadge:'بوابة الجملة المعتمدة · Pure Pets B2B',perkCarton:'كراتين وعبوات',perkPrice:'أسعار جملة فورية',perkFree:'تصفح حر مباشر',
    themeToggle:'تبديل المظهر'
  },
  en: {
    top:'The Pure Pets business gateway',wholesale:'A dedicated wholesale experience',navCatalog:'Products',navOrders:'My orders',
    cart:'Cart',login:'Sign in / Join',logout:'Sign out',eyebrow:'PURE PETS / BUSINESS',heroOne:'Care for them.',heroTwo:'Grow with us.',
    heroDesc:'Carefully chosen products, clear pack pricing, and a buying experience built around your business.',explore:'Explore the collection',
    guestHint:'Browse freely. Sign in only when you want to take action.',collection:'THE COLLECTION / WHOLESALE',catalogHeading:'Explore the collection',
    catalogHint:'Authorized wholesale products only, sold in cartons & bulk packs (no piece sales).',products:'products',search:'Search products...',
    sortFeatured:'Featured first',sortLow:'Price: low to high',sortHigh:'Price: high to low',loadMore:'Load more',
    promiseOne:'Wholesale packs & cartons only',promiseTwo:'Verified wholesale pricing',promiseThree:'Orders tied to your account',footerCopy:'Everything your business needs, in one place.',
    advantageKicker:'AUTHORIZED WHOLESALE PACT · B2B EXCELLENCE',advantageTitle:'Wholesale Standards Engineered For Business Scale',advantageSubtitle:'An integrated commercial and logistics ecosystem delivering verified product integrity and superior retail margins.',
    promiseOneBadge:'Cartons & Packs Only',promiseOneDesc:'Direct-from-source commercial bulk packs engineered for retail stores, clinics, and high-volume breeders without intermediaries.',
    promiseOneBullet1:'Transparent economic pack sizing',promiseOneBullet2:'No piece sales (distributor margin protection)',
    promiseTwoBadge:'Live Verified Rates',promiseTwoDesc:'Transparent rate cards with instant digital commercial invoices and guaranteed tier-based wholesale pricing.',
    promiseTwoBullet1:'Competitive tiered price scales',promiseTwoBullet2:'Instant downloadable commercial invoices',
    promiseThreeBadge:'Instant Account Sync',promiseThreeDesc:'Real-time order tracking, comprehensive invoice archive, and priority dispatch from the designated Al Haram Hub.',
    promiseThreeBullet1:'Priority preparation & fast dispatch',promiseThreeBullet2:'Automated routing to Al Haram Central Hub',
    telemetryLiveStatus:'Wholesale Network Operational',telemetryHubLabel:'Central Fulfillment Hub: Al Haram (Designated Pure Pets Stock)',telemetryConcierge:'B2B Sales Concierge (WhatsApp)',
    footerBrandDesc:'Everything your business needs, in one place. Qatar’s premier wholesale platform supplying verified retailers, veterinary clinics, and licensed breeders.',
    footerColCatalog:'Catalog & Supply',footerLinkAll:'All Wholesale Products',footerLinkPacks:'Bulk Food & Nutrition',footerLinkCare:'Care & Veterinary Supplies',footerLinkNew:'New Wholesale Arrivals',
    footerColBuyer:'Buyer Workspace',footerLinkCart:'Cart & Active Workspace',footerLinkOrders:'My Orders & Invoices',footerLinkAccount:'Business Account Sign In',footerLinkStaff:'Staff Operations Desk',
    footerColReach:'Logistics & Support',footerReachDesc:'Express commercial dispatch covering all Qatar municipalities:',footerSupportPhone:'Support Hotline: +974 5999 7720',
    footerQatarVerified:'Licensed & Verified Platform · Qatar',footerVetInspected:'Veterinary-Inspected Supply',
    footerLegalCopy:'© 2026 Pure Pets Wholesale Platform W.L.L. All rights reserved across the State of Qatar.',
    footerLegalStewardship:'All wholesale transactions and animal welfare standards strictly adhere to the laws and regulations of Qatar.',
    footerAscend:'Top',doha:'Doha',alrayyan:'Al Rayyan',alwakrah:'Al Wakrah',alkhor:'Al Khor',lusail:'Lusail',alshamal:'Al Shamal',
    workspace:'Your wholesale workspace',authTitle:'Welcome to wholesale',authIntro:'Sign in to continue right where you left off.',
    loginTab:'Sign in',registerTab:'Create account',email:'Email address',password:'Password',continue:'Continue',
    all:'All',emptyTitle:'No matching products',emptyText:'Try a different search or category.',
    unavailableTitle:'Catalog temporarily unavailable',unavailableText:'We could not load the wholesale catalog. The product service may still be getting configured.',
    retry:'Try again',starting:'Loading collection...',startingAuth:'Checking your session...',from:'From',perPack:'per pack',
    soldOut:'Currently unavailable',add:'Add to cart',save:'Save for later',details:'Product details',selectPack:'Pack / selling unit',quantity:'Number of packs',
    noAccount:'Please sign in first',cartEmpty:'Your cart is empty',savedEmpty:'No saved items yet',
    ordersEmpty:'No wholesale requests yet',cartHeading:'Wholesale cart',savedHeading:'Saved products',ordersHeading:'My orders',
    remove:'Remove',requestOrder:'Submit wholesale request',total:'Estimated total',branch:'Fulfillment branch',
    branchMissing:'No ordering branch is currently published. You can browse and save items, but order submission is temporarily unavailable.',
    draftNote:'Requests are not paid or confirmed until reviewed by Pure Pets. All prices and stock are verified again on the server.',
    signedIn:'Signed in successfully',added:'Added to your cart',saved:'Product saved',requestSent:'Wholesale request submitted for review',
    saveFailed:'Could not save. Please retry.',removed:'Removed',comingSoon:'This product is currently unavailable',
    authFailed:'Sign in failed. Check your details or registration settings.',sessionFailed:'Could not verify your account.',
    processing:'Working...',requestFailed:'Could not submit the request. Refresh prices or stock and retry.',
    noProducts:'No published wholesale products yet.',signupConfirm:'Create your account to continue.',welcome:'My account',open:'Open',status:'Status',
    units:'units',verified:'Wholesale price',noBranch:'Select branch',cancelRequest:'Cancel request',cancelConfirm:'Cancel this pending wholesale request?',cancelSuccess:'Request cancelled',increase:'Increase quantity',decrease:'Decrease quantity',
    availableStock:'Available stock',outOfStock:'Out of stock',inCart:'In cart',packsInCart:'packs in cart',packs:'packs',alreadyInCart:'Currently in cart',
    fulfillmentBranch:'Fulfillment Branch (iOS App Designated)',assignedBranchLabel:'Fulfillment & Dispatch Branch',consumerAppBranchNote:'Automatically routed to the Pure Pets consumer app stock branch (Al Haram)',
    googleSignIn:'Continue with Google',appleSignIn:'Continue with Apple',orDivider:'or',tabEmail:'Email address',tabPhone:'Phone number',
    phoneNumber:'Phone number',sendCode:'Send verification code (SMS)',codeSentTo:'Verification code sent to:',
    changePhone:'Change number',smsCode:'Verification code (6 digits)',verifyCode:'Verify and sign in',
    resendCode:'Resend code',codeResent:'Verification code resent',invalidPhone:'Please enter a valid phone number (e.g. +97455551234)',
    invalidCode:'Invalid verification code. Please check and retry.',phoneQuota:'SMS quota exceeded. Please try again later.',
    resetFilters:'Reset filters',activeFilters:'Active filters:',allCount:'wholesale items',
    heroBadge:'Authorized Wholesale Portal · Pure Pets B2B',perkCarton:'Cartons & Packs',perkPrice:'Live Wholesale Rates',perkFree:'Direct Free Browse',
    themeToggle:'Toggle appearance'
  }
};
const state = {
  lang: 'ar', theme: 'light', products: [], cursor:null, categories:[], category:'all', query:'', sort:'featured',
  branches:[], assignedBranch:{ id:'qQX5tQikeluPnOH2W7RT', nameAr:'الهرم', nameEn:'Al Haram (Consumer Stock)', isConsumerAppStock:true },
  cart:[], saved:[], user:null, backend:null, pending:null, activeProduct:null,
  authMode:'login', authMethod:'email', phoneStep:'input', phoneConfirmation:null, recaptchaVerifier:null, lastPhone:'',
  drawer:'cart', loadError:false, authReady:false, loading:false,
  submitting:false, orderCommandId:null, ordersLoading:false,ordersError:false,orders:[], notifyTimer:null
};
const phrase = (key) => t[state.lang][key] || key;
const esc = (value) => String(value == null ? '' : value).replace(/[&<>"']/g,(c)=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const localized = (obj) => (state.lang === 'ar' ? (obj.nameAr || obj.nameEn) : (obj.nameEn || obj.nameAr)) || '';
const money = (minor, currency) => {
  try { return new Intl.NumberFormat(state.lang === 'ar' ? 'ar' : 'en', {style:'currency',currency:currency || 'QAR',maximumFractionDigits:2}).format((minor || 0)/100); }
  catch { return String(((minor||0)/100).toFixed(2)) + ' ' + (currency || 'QAR'); }
};
function toast(text) {
  const node=$('toast');node.textContent=text;node.hidden=false;
  if (state.notifyTimer) clearTimeout(state.notifyTimer);
  state.notifyTimer=setTimeout(()=>{node.hidden=true;},4200);
}
function applyLanguage() {
  document.documentElement.lang=state.lang;
  document.documentElement.dir=state.lang==='ar'?'rtl':'ltr';
  document.querySelectorAll('[data-t]').forEach(node=>{
    const key=node.dataset.t;
    if(Object.hasOwn(t[state.lang],key))node.textContent=phrase(key);
  });
  document.querySelectorAll('[data-placeholder]').forEach(node=>node.placeholder=phrase(node.dataset.placeholder));
  $('languageBtn').textContent=state.lang==='ar'?'EN':'عربي';
  $('accountBtn').textContent=state.user ? phrase('welcome') : phrase('login');
  document.title=state.lang==='ar'?'Pure Pets | طلبات الجملة':'Pure Pets | Wholesale ordering';
  const labels={savedBtn:phrase('savedHeading'),searchInput:phrase('search'),sortTriggerBtn:phrase('sortFeatured'),themeToggleBtn:phrase('themeToggle'),closeProduct:state.lang==='ar'?'إغلاق التفاصيل':'Close details',closeAuth:state.lang==='ar'?'إغلاق تسجيل الدخول':'Close sign in',closeDrawer:state.lang==='ar'?'إغلاق اللوحة':'Close panel'};
  Object.entries(labels).forEach(([id,label])=>$(id)?.setAttribute('aria-label',label));

  const langArBtn = $('wsFooterLangAr');
  const langEnBtn = $('wsFooterLangEn');
  if (langArBtn && langEnBtn) {
    langArBtn.classList.toggle('active', state.lang === 'ar');
    langArBtn.setAttribute('aria-checked', state.lang === 'ar' ? 'true' : 'false');
    langEnBtn.classList.toggle('active', state.lang === 'en');
    langEnBtn.setAttribute('aria-checked', state.lang === 'en' ? 'true' : 'false');
  }
  updateWsFooterClock();

  applyTheme(state.theme || 'light');
  renderCatalog(); renderDrawer();
}

function updateWsFooterClock() {
  const clockEl = $('ws-footer-clock');
  if (!clockEl) return;
  try {
    const now = new Date();
    const isArabic = state.lang === 'ar';
    const timeStr = now.toLocaleTimeString(isArabic ? 'ar-QA' : 'en-US', {
      timeZone: 'Asia/Qatar',
      hour: '2-digit',
      minute: '2-digit',
      hour12: true
    });
    clockEl.textContent = `${timeStr} ${isArabic ? 'بتوقيت قطر' : 'AST'}`;
  } catch {
    clockEl.textContent = state.lang === 'ar' ? 'الدوحة · توقيت قطر' : 'Doha · AST';
  }
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
  if (metaTheme) metaTheme.setAttribute('content', theme === 'dark' ? '#090d14' : '#faf9f6');
  const btn = $('themeToggleBtn');
  if (btn) {
    btn.setAttribute('data-current-theme', theme);
    const label = state.lang === 'ar'
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
function goAuth(intent) {
  if (state.user) return runIntent(intent);
  state.pending=intent;
  state.authMode='login';
  setAuthMethod('email');
  setPhoneStep('input');
  updateAuthTabs();
  $('authError').hidden=true;
  if(!$('authDialog').open)$('authDialog').showModal();
  $('emailInput').focus();
}
function setAuthMethod(method) {
  state.authMethod = method;
  const isEmail = method === 'email';
  $('methodEmailTab').classList.toggle('active', isEmail);
  $('methodPhoneTab').classList.toggle('active', !isEmail);
  $('emailAuthSection').hidden = !isEmail;
  $('phoneAuthSection').hidden = isEmail;
  $('authError').hidden = true;
  if (isEmail) {
    $('emailInput').focus();
  } else {
    setPhoneStep('input');
  }
}
function setPhoneStep(step) {
  state.phoneStep = step;
  const isInput = step === 'input';
  $('phoneInputForm').hidden = !isInput;
  $('phoneCodeForm').hidden = isInput;
  $('authError').hidden = true;
  if (isInput) {
    $('phoneInput').focus();
  } else {
    $('sentPhoneDisplay').textContent = state.lastPhone;
    $('phoneCodeInput').value = '';
    $('phoneCodeInput').focus();
  }
}
function updateAuthTabs() {
  $('loginTab').classList.toggle('active',state.authMode==='login');
  $('registerTab').classList.toggle('active',state.authMode==='register');
  $('loginTab').setAttribute('aria-pressed',String(state.authMode==='login'));
  $('registerTab').setAttribute('aria-pressed',String(state.authMode==='register'));
  $('passwordInput').autocomplete=state.authMode==='login'?'current-password':'new-password';
}
async function call(name, payload={}) {
  if (!state.backend) throw new Error('The wholesale backend is not connected');
  const response=await state.backend.invoke(name,payload);
  return response || {};
}
async function connectBackend() {
  let config;
  try {
    const res = await fetch('/ws/api/config', {cache: 'no-store'});
    if (res.ok) config = await res.json();
  } catch (err) {
    console.warn('Storefront config fetch deferred:', err?.message);
  }
  if (!config || !config.firebase || !config.firebase.apiKey) {
    config = {
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

  const [{initializeApp},{getAuth,onAuthStateChanged,signInWithEmailAndPassword,createUserWithEmailAndPassword,signOut,GoogleAuthProvider,OAuthProvider,signInWithPopup,signInWithRedirect,getRedirectResult,RecaptchaVerifier,signInWithPhoneNumber},{getFunctions,httpsCallable},{initializeAppCheck,ReCaptchaEnterpriseProvider},{getFirestore,collection,getDocs,query,where,limit:fbLimit,startAfter}]
  = await Promise.all([
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-functions.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app-check.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js')
  ]);

  const app=initializeApp(config.firebase,'pure-pets-wholesale');
  if(config.appCheckSiteKey) {
    try {
      initializeAppCheck(app,{provider:new ReCaptchaEnterpriseProvider(config.appCheckSiteKey),isTokenAutoRefreshEnabled:true});
    } catch(err) {
      console.warn('AppCheck initialization skipped:', err?.message);
    }
  }

  const auth=getAuth(app);
  const functions=getFunctions(app,config.region||'us-central1');
  const db=getFirestore(app);

  state.backend={
    auth,signInWithEmailAndPassword,createUserWithEmailAndPassword,signOut,
    GoogleAuthProvider,OAuthProvider,signInWithPopup,signInWithRedirect,getRedirectResult,RecaptchaVerifier,signInWithPhoneNumber,
    db,collection,getDocs,query,where,fbLimit,startAfter,
    invoke:async(name,payload)=> (await httpsCallable(functions,name,{timeout:25000})(payload)).data
  };

  try {
    getRedirectResult(auth).then((result)=>{
      if(result?.user){
        if($('authDialog').open)$('authDialog').close();
        toast(phrase('signedIn'));
      }
    }).catch((err)=>{
      console.warn('Redirect sign-in error:', err?.code, err?.message);
      if(err?.code && err.code !== 'auth/credential-already-in-use'){
        $('authError').textContent = (err.message || phrase('authFailed')) + ` (${err.code})`;
        $('authError').hidden = false;
        if(!$('authDialog').open)$('authDialog').showModal();
      }
    });
  } catch(e) {
    console.warn('getRedirectResult caught:', e);
  }

  onAuthStateChanged(auth, async (user)=>{
    state.user=user||null; state.authReady=true; state.cart=[];state.saved=[];state.orders=[];state.orderCommandId=null;
    $('accountBtn').textContent=user?phrase('welcome'):phrase('login');
    if(user) {
      if($('authDialog').open)$('authDialog').close();
      toast(phrase('signedIn'));
      try {
        const record=await call('getWholesaleBuyerState');
        state.cart=Array.isArray(record.cart)?record.cart:[];
        state.saved=Array.isArray(record.saved)?record.saved:[];
      } catch (error) {
        try {
          const cachedCart = JSON.parse(localStorage.getItem('pp_ws_cart_' + user.uid) || '[]');
          const cachedSaved = JSON.parse(localStorage.getItem('pp_ws_saved_' + user.uid) || '[]');
          state.cart = Array.isArray(cachedCart) ? cachedCart : [];
          state.saved = Array.isArray(cachedSaved) ? cachedSaved : [];
        } catch {}
      }
    }
    $('cartCount').textContent=String(state.cart.reduce((sum,line)=>sum+(Number(line.quantity)||0),0));
    renderDrawer();renderCatalog();
    if(user && state.pending) {
      const intent=state.pending;state.pending=null;
      try {await runIntent(intent);} catch(e){toast(e.message||phrase('saveFailed'));}
    }
  });
}
async function loadCatalog(reset=false) {
  if (state.loading) return;
  state.loading=true;state.loadError=false;
  $('catalogStatus').textContent=phrase('starting');
  if(reset){state.cursor=null;state.lastDocSnap=null;state.products=[];}
  renderCatalog();

  let items = null;
  let nextCursor = null;
  let branches = [];

  if (state.backend?.db) {
    try {
      const {db, collection, getDocs, query, where, fbLimit, startAfter} = state.backend;
      let q = query(collection(db, 'petAccessories'), where('wholesalePrice', '>', 0), fbLimit(50));
      if (state.cursor && state.lastDocSnap) {
        q = query(collection(db, 'petAccessories'), where('wholesalePrice', '>', 0), startAfter(state.lastDocSnap), fbLimit(50));
      }
      const snap = await getDocs(q);
      const docs = [];
      let lastSnap = null;
      snap.forEach(d => {
        lastSnap = d;
        const data = d.data();
        if (data.isDeleted === true || data.isBlocked === true || data.active === false) return;
        docs.push({ id: d.id, ...data });
      });

      if (lastSnap && snap.docs.length >= 50) {
        state.lastDocSnap = lastSnap;
        nextCursor = lastSnap.id;
      } else {
        state.lastDocSnap = null;
        nextCursor = null;
      }

      items = docs.map(doc => {
        const wholesaleUnitPrice = Number(doc.wholesalePrice) > 0 ? Number(doc.wholesalePrice) : 0;
        const hasWholesaleGroup = Array.isArray(doc.quantityGroups) && doc.quantityGroups.some(g => g && g.wholesaleEnabled === true && g.active !== false);
        const isWholesaleAllowed = (wholesaleUnitPrice > 0) || (doc.wholesaleEnabled === true) || hasWholesaleGroup;

        // Strictly exclude products without authorized wholesale selling
        if (!isWholesaleAllowed) return null;

        let groups = [];
        if (Array.isArray(doc.quantityGroups) && doc.quantityGroups.length > 0) {
          // Strictly reject single pieces (unitsPerGroup <= 1, id === 'single', name === 'حبة')
          groups = doc.quantityGroups
            .filter(g => g && g.active !== false && g.wholesaleEnabled === true && Number(g.unitsPerGroup) > 1 &&
              g.id !== 'single' && g.nameAr !== 'حبة' && g.nameAr !== 'حبة مفرقة' &&
              g.nameEn?.toLowerCase() !== 'piece' && g.nameEn?.toLowerCase() !== 'single'
            )
            .map(g => ({
              id: g.id,
              nameAr: g.nameAr || `عبوة (${g.unitsPerGroup} حبة)`,
              nameEn: g.nameEn || `Pack (${g.unitsPerGroup} pcs)`,
              unitsPerGroup: Number(g.unitsPerGroup),
              priceMinor: Number.isSafeInteger(g.wholesalePriceMinor)
                ? g.wholesalePriceMinor
                : Math.round(Number(g.wholesalePrice || wholesaleUnitPrice || 10) * Number(g.unitsPerGroup) * 100),
              active: true,
              wholesaleEnabled: true,
              defaultForWholesale: Boolean(g.defaultForWholesale)
            }));
        }

        // When no multi-unit wholesale groups were defined in quantityGroups, but wholesale is allowed:
        // Generate ONLY wholesale packages (cartons / packs / half cartons) — NEVER by piece!
        if (!groups.length && wholesaleUnitPrice > 0) {
          const isCanOrWet = /موتشي|طعام رطب|علبة|can|wet/i.test(doc.name || doc.nameEn || '');
          const isLargeBag = /20k|20\s*ك|24\s*ل|12\s*ك/i.test(doc.name || doc.nameEn || '');

          if (isCanOrWet) {
            groups = [
              {
                id: 'carton_24',
                nameAr: 'كرتون (24 علبة)',
                nameEn: 'Master Carton (24 cans)',
                unitsPerGroup: 24,
                priceMinor: Math.round(wholesaleUnitPrice * 24 * 100),
                active: true,
                wholesaleEnabled: true,
                defaultForWholesale: true
              },
              {
                id: 'pack_12',
                nameAr: 'نصف كرتون (12 علبة)',
                nameEn: 'Half Carton (12 cans)',
                unitsPerGroup: 12,
                priceMinor: Math.round(wholesaleUnitPrice * 12 * 100),
                active: true,
                wholesaleEnabled: true,
                defaultForWholesale: false
              }
            ];
          } else if (isLargeBag) {
            groups = [
              {
                id: 'bundle_6',
                nameAr: 'شدّة جملة (6 أكياس)',
                nameEn: 'Wholesale Bundle (6 sacks)',
                unitsPerGroup: 6,
                priceMinor: Math.round(wholesaleUnitPrice * 6 * 100),
                active: true,
                wholesaleEnabled: true,
                defaultForWholesale: true
              },
              {
                id: 'bundle_3',
                nameAr: 'نصف شدّة (3 أكياس)',
                nameEn: 'Half Bundle (3 sacks)',
                unitsPerGroup: 3,
                priceMinor: Math.round(wholesaleUnitPrice * 3 * 100),
                active: true,
                wholesaleEnabled: true,
                defaultForWholesale: false
              }
            ];
          } else {
            groups = [
              {
                id: 'carton_12',
                nameAr: 'كرتون (12 حبة)',
                nameEn: 'Carton (12 pcs)',
                unitsPerGroup: 12,
                priceMinor: Math.round(wholesaleUnitPrice * 12 * 100),
                active: true,
                wholesaleEnabled: true,
                defaultForWholesale: true
              },
              {
                id: 'pack_6',
                nameAr: 'نصف كرتون (6 حبات)',
                nameEn: 'Half Carton (6 pcs)',
                unitsPerGroup: 6,
                priceMinor: Math.round(wholesaleUnitPrice * 6 * 100),
                active: true,
                wholesaleEnabled: true,
                defaultForWholesale: false
              }
            ];
          }
        }

        if (!groups.length) return null;

        const image = doc.image || (Array.isArray(doc.imageURLsArray) && doc.imageURLsArray[0]) || '';

        let category = 'other';
        const docName = ((doc.name || '') + ' ' + (doc.nameEn || '')).toLowerCase();
        if (doc.petMainCategoryID === 5 || /قطط|قطة|موتشي|سيلكت|كيتي|cat/i.test(docName)) category = 'cats';
        else if (doc.petMainCategoryID === 1 || /طير|طيور|ببغاء|بادجي|كناري|سيرلاك|bird|parrot/i.test(docName)) category = 'birds';
        else if (doc.petMainCategoryID === 6 || /كلاب|كلب|dog/i.test(docName)) category = 'dogs';

        const rawQty = Number(doc.quantity);
        const available = Number.isFinite(rawQty) ? Math.max(0, Math.floor(rawQty)) : 0;

        return {
          id: doc.id,
          name: doc.name || doc.nameEn || '',
          nameAr: doc.name || '',
          nameEn: doc.nameEn || doc.name || '',
          category,
          image: typeof image === 'string' ? image : '',
          currency: doc.currency || 'QAR',
          available,
          groups
        };
      }).filter(Boolean);

      try {
        const bSnap = await getDocs(collection(db, 'branches'));
        const bDocs = [];
        bSnap.forEach(d => {
          const data = d.data();
          if (data.isActive !== false) {
            bDocs.push({
              id: d.id,
              nameAr: data.nameAr || (typeof data.name === 'object' ? data.name.ar : data.name) || '',
              nameEn: data.nameEn || (typeof data.name === 'object' ? data.name.en : data.name) || '',
              isConsumerAppStock: Boolean(data.isConsumerAppStock),
              isDefault: Boolean(data.isDefault)
            });
          }
        });
        if (bDocs.length) branches = bDocs;
      } catch (bErr) {
        console.warn('Branches fetch note:', bErr?.message);
      }

      if (!branches.length) {
        branches = [
          { id: 'qQX5tQikeluPnOH2W7RT', nameAr: 'الهرم', nameEn: 'Al Haram (Consumer Stock)', isConsumerAppStock: true },
          { id: 'Z3psFtT5vhfnFOncOtYX', nameAr: 'الوكرة , سوق واقف', nameEn: 'Wakra', isDefault: true }
        ];
      }

      const consumerBranch = branches.find(b => b.isConsumerAppStock === true)
        || branches.find(b => b.isDefault === true)
        || branches.find(b => b.id === 'qQX5tQikeluPnOH2W7RT')
        || branches[0]
        || { id: 'qQX5tQikeluPnOH2W7RT', nameAr: 'الهرم', nameEn: 'Al Haram', isConsumerAppStock: true };
      state.assignedBranch = consumerBranch;
      state.branches = branches;
    } catch (fbErr) {
      console.warn('Firestore fallback catalog query error:', fbErr?.message);
    }
  }

  if (items && items.length > 0) {
    const products = items.map(normalizeCatalogItem).filter(Boolean);
    const existing = new Map(state.products.map(item => [item.id, item]));
    products.forEach(item => existing.set(item.id, item));
    state.products = [...existing.values()];
    state.cursor = nextCursor;
    if (branches.length && !state.branches.length) state.branches = branches;
    state.loadError = false;
  } else if (!state.products.length) {
    state.loadError = true;
  }

  state.loading = false;
  $('catalogStatus').textContent = '';
  renderCatalog();
}
function categoryTitle(category) {
  if (category === 'all') return phrase('all');
  const known = {
    all: { ar: 'الكل', en: 'All' },
    cats: { ar: 'القطط', en: 'Cats' },
    birds: { ar: 'الطيور', en: 'Birds' },
    dogs: { ar: 'الكلاب', en: 'Dogs' },
    food: { ar: 'الأغذية', en: 'Food' }
  };
  return known[category] ? known[category][state.lang] : category;
}

const categoryIcons = {
  all: '✦',
  cats: '🐱',
  birds: '🦜',
  dogs: '🐶',
  food: '🥣',
  other: '📦'
};

function updateSortUI(sortValue) {
  const sortMap = {
    featured: { ar: 'الترتيب الافتراضي', en: 'Featured first' },
    priceAsc: { ar: 'الأقل سعراً', en: 'Price: low to high' },
    priceDesc: { ar: 'الأعلى سعراً', en: 'Price: high to low' }
  };
  const labelEl = $('sortLabel');
  if (labelEl) {
    labelEl.textContent = sortMap[sortValue] ? sortMap[sortValue][state.lang] : sortValue;
  }
  const sortOptions = document.querySelectorAll('.sort-option');
  sortOptions.forEach(opt => {
    const isSelected = opt.dataset.value === sortValue;
    opt.classList.toggle('selected', isSelected);
    opt.setAttribute('aria-selected', String(isSelected));
  });
}

function setSort(sortValue) {
  state.sort = sortValue;
  updateSortUI(sortValue);
  const menu = $('sortMenu');
  const btn = $('sortTriggerBtn');
  if (menu) menu.hidden = true;
  if (btn) btn.setAttribute('aria-expanded', 'false');
  renderCatalog();
}

function visibleProducts() {
  let products = state.products.filter(p => (state.category === 'all' || p.category === state.category)
    && (localized(p) + ' ' + p.id + ' ' + p.category).toLocaleLowerCase().includes(state.query.toLocaleLowerCase()));
  if (state.sort !== 'featured') products = [...products].sort((a, b) => ((a.groups[0]?.priceMinor || 0) - (b.groups[0]?.priceMinor || 0)) * (state.sort === 'priceDesc' ? -1 : 1));
  return products;
}

function renderCatalog() {
  const focusedCategory = document.activeElement?.dataset.category;
  const tabs = $('categoryTabs');
  if (tabs) {
    tabs.replaceChildren();
    const categories = ['all', ...new Set(state.products.map(p => p.category))];
    if (!categories.includes(state.category)) state.category = 'all';
    categories.forEach(category => {
      const count = category === 'all'
        ? state.products.length
        : state.products.filter(p => p.category === category).length;
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'category-pill' + (category === state.category ? ' active' : '');
      b.dataset.category = category;
      b.setAttribute('role', 'tab');
      b.setAttribute('aria-selected', String(category === state.category));
      b.innerHTML = `
        <span class="pill-icon" aria-hidden="true">${categoryIcons[category] || '✦'}</span>
        <span class="pill-label">${esc(categoryTitle(category))}</span>
        <span class="pill-badge">${count}</span>
      `;
      b.addEventListener('click', () => {
        state.category = category;
        renderCatalog();
      });
      tabs.append(b);
    });
    if (focusedCategory) Array.from(tabs.children).find(b => b.dataset.category === focusedCategory)?.focus();
  }

  // Active filters telemetry strip
  const filtersBar = $('activeFiltersBar');
  if (filtersBar) {
    const hasFilter = state.category !== 'all' || state.query !== '' || state.sort !== 'featured';
    if (hasFilter) {
      filtersBar.hidden = false;
      filtersBar.replaceChildren();

      const lead = document.createElement('span');
      lead.className = 'telemetry-lead';
      lead.textContent = phrase('activeFilters');
      filtersBar.append(lead);

      if (state.category !== 'all') {
        const chip = document.createElement('span');
        chip.className = 'telemetry-chip';
        chip.innerHTML = `${categoryIcons[state.category] || ''} ${esc(categoryTitle(state.category))} <button type="button" aria-label="Remove category">×</button>`;
        chip.querySelector('button').addEventListener('click', () => {
          state.category = 'all';
          renderCatalog();
        });
        filtersBar.append(chip);
      }

      if (state.query) {
        const chip = document.createElement('span');
        chip.className = 'telemetry-chip';
        chip.innerHTML = `"${esc(state.query)}" <button type="button" aria-label="Clear query">×</button>`;
        chip.querySelector('button').addEventListener('click', () => {
          state.query = '';
          const input = $('searchInput');
          if (input) input.value = '';
          const clear = $('searchClearBtn');
          if (clear) clear.hidden = true;
          renderCatalog();
        });
        filtersBar.append(chip);
      }

      if (state.sort !== 'featured') {
        const sortTitles = {
          priceAsc: state.lang === 'ar' ? 'الأقل سعراً' : 'Price: low to high',
          priceDesc: state.lang === 'ar' ? 'الأعلى سعراً' : 'Price: high to low'
        };
        const chip = document.createElement('span');
        chip.className = 'telemetry-chip';
        chip.innerHTML = `↕ ${sortTitles[state.sort] || state.sort} <button type="button" aria-label="Reset sort">×</button>`;
        chip.querySelector('button').addEventListener('click', () => {
          setSort('featured');
        });
        filtersBar.append(chip);
      }

      const resetBtn = document.createElement('button');
      resetBtn.type = 'button';
      resetBtn.className = 'telemetry-reset';
      resetBtn.innerHTML = `<span>${phrase('resetFilters')}</span>`;
      resetBtn.addEventListener('click', () => {
        state.category = 'all';
        state.query = '';
        state.sort = 'featured';
        const input = $('searchInput');
        if (input) input.value = '';
        const clear = $('searchClearBtn');
        if (clear) clear.hidden = true;
        updateSortUI('featured');
        renderCatalog();
      });
      filtersBar.append(resetBtn);
    } else {
      filtersBar.hidden = true;
    }
  }

  // Update Sort Label
  updateSortUI(state.sort);

  const list = visibleProducts();
  const countEl = $('productCount');
  if (countEl) countEl.textContent = String(list.length);
  const grid = $('productGrid');
  grid.setAttribute('aria-busy', String(state.loading));
  grid.replaceChildren();
  $('loadMoreBtn').hidden = !state.cursor || state.loading;
  if (state.loading && !state.products.length) {
    for (let i = 0; i < 8; i++) {
      const node = document.createElement('div');
      node.className = 'loading-card';
      grid.append(node);
    }
    return;
  }
  if (!list.length) {
    const el = document.createElement('div');
    el.className = 'empty-state';
    const title = document.createElement('strong');
    title.textContent = state.loadError ? phrase('unavailableTitle') : phrase('emptyTitle');
    const sub = document.createElement('p');
    sub.textContent = state.loadError ? phrase('unavailableText') : (state.products.length ? phrase('emptyText') : phrase('noProducts'));
    el.append(title, sub);
    if (!state.loadError && state.products.length && (state.query || state.category !== 'all')) {
      const r = document.createElement('button');
      r.type = 'button';
      r.className = 'secondary-button empty-reset-btn';
      r.textContent = phrase('resetFilters');
      r.addEventListener('click', () => {
        state.category = 'all';
        state.query = '';
        state.sort = 'featured';
        const input = $('searchInput');
        if (input) input.value = '';
        const clear = $('searchClearBtn');
        if (clear) clear.hidden = true;
        updateSortUI('featured');
        renderCatalog();
      });
      el.append(r);
    }
    if (state.loadError) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'secondary-button';
      b.textContent = phrase('retry');
      b.addEventListener('click', () => loadCatalog(true));
      el.append(b);
    }
    grid.append(el);
    return;
  }
  for(const item of list){
    const inCartQty = state.cart.filter(c => c.productId === item.id).reduce((sum, c) => sum + (Number(c.quantity) || 0), 0);
    const group=item.groups.find(g=>g.defaultForWholesale)||item.groups[0];
    const image=item.image?'<img src="'+esc(item.image)+'" loading="lazy" alt="'+esc(localized(item))+'">':'<span class="placeholder-art">PP</span>';
    const card=document.createElement('article');
    card.className='product-card' + (inCartQty > 0 ? ' in-cart' : '');

    const cartBadge = inCartQty > 0
      ? '<span class="in-cart-badge"><span class="badge-icon">🛒</span> <span class="badge-count">' + inCartQty + '</span> ' + esc(phrase('packsInCart')) + '</span>'
      : '';

    const stockBadge = '<div class="card-available ' + (item.available > 0 ? 'in-stock' : 'out-of-stock') + '">' +
      '<span class="stock-dot" aria-hidden="true"></span>' +
      '<span class="stock-text">' + (item.available > 0 ? (esc(phrase('availableStock')) + ': ' + item.available + ' ' + esc(phrase('units'))) : esc(phrase('outOfStock'))) + '</span>' +
      '</div>';

    const actionUI = inCartQty > 0
      ? '<div class="cell-stepper" role="group" aria-label="' + esc(phrase('quantity')) + '">' +
          '<button type="button" class="stepper-btn stepper-sub" data-stepper-sub="' + esc(item.id) + '" aria-label="' + esc(phrase('decrease')) + '">−</button>' +
          '<span class="stepper-val" title="' + esc(phrase('inCart')) + '">' + inCartQty + '</span>' +
          '<button type="button" class="stepper-btn stepper-add" data-stepper-add="' + esc(item.id) + '" aria-label="' + esc(phrase('increase')) + '">+</button>' +
        '</div>'
      : '<button class="add-mini" type="button" data-quick-add="' + esc(item.id) + '" data-group-id="' + esc(group.id) + '" aria-label="' + esc(phrase('add')) + '">+</button>';

    card.innerHTML='<button class="product-art" type="button" data-open="'+esc(item.id)+'" aria-label="'+esc(localized(item))+'">'+image+
      '<span class="pack-chip">'+esc(String(group.unitsPerGroup))+' '+esc(phrase('units'))+'</span>'+
      cartBadge+
      '</button>'+
      '<button type="button" class="save-float" data-save="'+esc(item.id)+'" aria-pressed="'+String(state.saved.includes(item.id))+'" aria-label="'+esc(phrase('save'))+'">'+(state.saved.includes(item.id)?'♥':'♡')+'</button>'+
      '<div class="card-body">'+
      '<div class="card-type">'+esc(categoryTitle(item.category))+'</div>'+
      '<h3 data-open="'+esc(item.id)+'" role="button" tabindex="0">'+esc(localized(item))+'</h3>'+
      '<p class="card-pack">'+esc(localized(group))+' · '+esc(String(group.unitsPerGroup))+' '+esc(phrase('units'))+'</p>'+
      stockBadge+
      '<div class="card-bottom"><div><span class="price-label">'+esc(phrase('from'))+'</span><div class="price-value">'+esc(money(group.priceMinor,item.currency))+'</div></div>'+
      actionUI+'</div></div>';
    grid.append(card);
  }
}
function getProduct(id){return state.products.find(p=>p.id===id);}
function productDetails(id){
  const product=getProduct(id);if(!product)return;
  state.activeProduct=id;
  const inCartQty = state.cart.filter(c => c.productId === product.id).reduce((sum, c) => sum + (Number(c.quantity) || 0), 0);
  const image=product.image?'<img src="'+esc(product.image)+'" alt="'+esc(localized(product))+'">':'<span class="placeholder-art">PP</span>';
  const dialog=$('productDialog');
  $('productDetail').innerHTML='<div class="detail-layout"><div class="detail-image">'+image+'</div>'+
    '<div class="detail-info"><div class="section-kicker">'+esc(phrase('verified'))+'</div><h2>'+esc(localized(product))+'</h2>'+
    '<p class="detail-category">'+esc(categoryTitle(product.category))+'</p>'+
    '<div class="detail-stock ' + (product.available > 0 ? 'in-stock' : 'out-of-stock') + '">' +
      '<span class="stock-dot" aria-hidden="true"></span>' +
      '<span>' + (product.available > 0 ? (esc(phrase('availableStock')) + ': <strong>' + product.available + '</strong> ' + esc(phrase('units'))) : ('<strong>' + esc(phrase('outOfStock')) + '</strong>')) + '</span>' +
    '</div>' +
    (inCartQty > 0 ? '<div class="detail-in-cart-note">🛒 ' + esc(phrase('alreadyInCart')) + ': <strong>' + inCartQty + ' ' + esc(phrase('packs')) + '</strong></div>' : '') +
    '<label>'+esc(phrase('selectPack'))+'<select id="detailGroup">'+
    product.groups.map(g=>'<option value="'+esc(g.id)+'">'+esc(localized(g))+' · '+esc(g.unitsPerGroup)+' '+esc(phrase('units'))+' · '+esc(money(g.priceMinor,product.currency))+'</option>').join('')+
    '</select></label><label>'+esc(phrase('quantity'))+'<input id="detailQuantity" type="number" min="1" max="10000" step="1" value="1"></label>'+
    '<button class="primary-button" id="detailAdd" type="button">'+esc(phrase('add'))+'</button></div></div>';
  $('detailAdd').addEventListener('click',()=>{
    const groupId=$('detailGroup').value;
    const quantity=Number($('detailQuantity').value);
    try {
      const intent=protectedIntent('add',{productId:product.id,groupId,quantity});
      dialog.close();requireBuyer(intent);
    } catch {toast(phrase('requestFailed'));}
  });
  $('detailGroup').value=(product.groups.find(g=>g.defaultForWholesale)||product.groups[0]).id;
  if(!dialog.open)dialog.showModal();
}
function requireBuyer(intent){
  if(!state.user){goAuth(intent);return;}
  runIntent(intent).catch(e=>toast(e.message||phrase('saveFailed')));
}
async function persistBuyer(cart,saved){
  if(!state.user)throw new Error(phrase('noAccount'));
  try {
    const response=await call('saveWholesaleBuyerState',{cart,saved});
    state.cart=Array.isArray(response.cart)?response.cart:cart;
    state.saved=Array.isArray(response.saved)?response.saved:saved;
  } catch(err) {
    console.info('Remote buyer state save deferred; persisting locally:', err?.message);
    state.cart=cart;
    state.saved=saved;
    try {
      localStorage.setItem('pp_ws_cart_' + state.user.uid, JSON.stringify(cart));
      localStorage.setItem('pp_ws_saved_' + state.user.uid, JSON.stringify(saved));
    } catch {}
  }
  $('cartCount').textContent=String(state.cart.reduce((sum,x)=>sum+x.quantity,0));
  renderDrawer();renderCatalog();
}
async function runIntent(intent) {
  if(!state.user)return goAuth(intent);
  if(intent.action==='add'){
    await persistBuyer(mergeCart(state.cart,{productId:intent.productId,groupId:intent.groupId,quantity:intent.quantity}),state.saved);
    toast(phrase('added'));
  } else if(intent.action==='save'){
    await persistBuyer(state.cart,[...new Set([...state.saved,intent.productId])]);
    toast(phrase('saved'));
  } else if(intent.action==='cart'||intent.action==='checkout') openDrawer('cart');
  else if(intent.action==='orders') await openDrawer('orders');
  else if(intent.action==='saved') await openDrawer('saved');
}
function cartLinePrice(line){
  const product=getProduct(line.productId);
  const group=product?.groups.find(x=>x.id===line.groupId);
  return group ? group.priceMinor*line.quantity : null;
}
function formatDrawerRows(lines,mode) {
  if(!lines.length)return '<div class="empty-state"><strong>'+esc(phrase(mode==='cart'?'cartEmpty':'savedEmpty'))+'</strong></div>';
  return lines.map((line,index)=>{
    const id=mode==='cart'?line.productId:line;
    const product=getProduct(id);
    const group=mode==='cart'?product?.groups.find(x=>x.id===line.groupId):null;
    const label=product?localized(product):id;
    const price=mode==='cart'&&group?money(group.priceMinor*line.quantity,product.currency):'';
    return '<div class="drawer-item"><div><strong>'+esc(label)+'</strong><small>'+
      (mode==='cart'?esc(String(line.quantity)+' × '+(group?localized(group):line.groupId)):'')+'</small>'+
      '<small>'+esc(price)+'</small></div><div class="drawer-actions">'+(mode==='cart'?'<button type="button" data-adjust="'+index+':-1" aria-label="'+esc(phrase('decrease'))+'">−</button><button type="button" data-adjust="'+index+':1" aria-label="'+esc(phrase('increase'))+'">+</button>':'<button type="button" data-view="'+esc(id)+'" aria-label="'+esc(phrase('details'))+'">↗</button>')+'<button type="button" data-remove="'+mode+':'+index+'" aria-label="'+esc(phrase('remove'))+'">×</button></div></div>';
  }).join('');
}
function renderDrawer(){
  if($('buyerDrawer').hidden)return;
  const view=state.drawer;
  $('drawerHeading').textContent=phrase(view==='cart'?'cartHeading':view==='saved'?'savedHeading':'ordersHeading');
  const box=$('drawerContent');
  const selectedBranch=$('branchSelect')?.value;
  if(view==='orders'&&(state.ordersLoading||state.ordersError)){
    box.replaceChildren();
    const message=document.createElement('p');message.className='notice';message.setAttribute('role','status');message.textContent=state.ordersLoading?phrase('processing'):phrase('saveFailed');box.append(message);
    if(state.ordersError){const retry=document.createElement('button');retry.className='secondary-button';retry.textContent=phrase('retry');retry.addEventListener('click',()=>openDrawer('orders'));box.append(retry);}
    return;
  }
  if(view==='cart'){
    const total=state.cart.reduce((n,line)=>n+(cartLinePrice(line)||0),0);
    const assignedBranchName = esc(localized(state.assignedBranch) || state.assignedBranch?.nameAr || 'الهرم');
    box.innerHTML=formatDrawerRows(state.cart,'cart')+
      (state.cart.length?'<div class="drawer-total"><span>'+esc(phrase('total'))+'</span><strong>'+esc(money(total,state.products[0]?.currency||'QAR'))+'</strong></div>'+
      '<div class="drawer-assigned-branch">'+
        '<div class="branch-pill-icon" aria-hidden="true">🏢</div>'+
        '<div class="branch-pill-details">'+
          '<span class="branch-pill-kicker">'+esc(phrase('assignedBranchLabel'))+'</span>'+
          '<strong class="branch-pill-name">'+assignedBranchName+'</strong>'+
          '<span class="branch-pill-note">'+esc(phrase('consumerAppBranchNote'))+'</span>'+
        '</div>'+
      '</div>'+
      '<button type="button" class="primary-button" id="checkoutBtn">'+esc(phrase('requestOrder'))+'</button>'+
      '<p class="notice">'+esc(phrase('draftNote'))+'</p>':'');
    $('checkoutBtn')?.addEventListener('click',()=>submitOrder());
  } else if(view==='saved') box.innerHTML=formatDrawerRows(state.saved,'saved');
  else box.innerHTML=state.orders.length?state.orders.map(o=>'<div class="drawer-item"><div><strong>#'+esc(o.orderNumber||o.id)+'</strong><small>'+esc(o.status||'pending_review')+'</small><small>'+esc(money(o.totalMinor,o.currency))+'</small></div>'+ (o.status==='pending_review'?'<button type="button" data-cancel="'+esc(o.id)+'" title="'+esc(phrase('cancelRequest'))+'">'+esc(phrase('cancelRequest'))+'</button>':'')+'</div>').join(''):'<div class="empty-state"><strong>'+esc(phrase('ordersEmpty'))+'</strong></div>';
}
let drawerReturnFocus=null;
function setWorkspaceInert(value){
  document.querySelectorAll('.skip-link,.topbar,.site-header,main,.footer').forEach(node=>node.inert=value);
  document.body.classList.toggle('workspace-open',value);
}
async function openDrawer(view){
  if(!state.user)return goAuth(protectedIntent(view==='orders'?'orders':view==='saved'?'saved':'cart'));
  if($('buyerDrawer').hidden)drawerReturnFocus=document.activeElement;
  setWorkspaceInert(true);
  state.drawer=view; $('buyerDrawer').hidden=false;$('drawerScrim').hidden=false;
  if(view==='orders'){
    state.ordersLoading=true;state.ordersError=false;renderDrawer();$('closeDrawer').focus();
    try{const data=await call('listWholesaleOrderRequests',{limit:30});state.orders=Array.isArray(data.items)?data.items:[];}
    catch{state.ordersError=true;}
    finally{state.ordersLoading=false;}
  }
  if(!$('buyerDrawer').hidden){renderDrawer();$('closeDrawer').focus();}
}
function closeDrawer(){$('buyerDrawer').hidden=true;$('drawerScrim').hidden=true;setWorkspaceInert(false);drawerReturnFocus?.focus();}
$('buyerDrawer').addEventListener('keydown',event=>{
  if(event.key==='Escape'){event.preventDefault();closeDrawer();return;}
  if(event.key!=='Tab')return;
  const nodes=[...$('buyerDrawer').querySelectorAll('button:not(:disabled),input,select,a[href],textarea')].filter(n=>n.getClientRects().length);
  const first=nodes[0],last=nodes.at(-1);
  if(event.shiftKey&&document.activeElement===first){event.preventDefault();last?.focus();}
  else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first?.focus();}
});
$('authDialog').addEventListener('cancel',()=>{state.pending=null;});
async function submitOrder(){
  if(state.submitting)return;
  const branchId = state.assignedBranch?.id || 'qQX5tQikeluPnOH2W7RT';
  if(!branchId){toast(phrase('branchMissing'));return;}
  if(!state.cart.length)return;
  state.submitting=true;
  const button=$('checkoutBtn');if(button){button.disabled=true;button.textContent=phrase('processing');}
  if(!state.orderCommandId)state.orderCommandId=crypto.randomUUID();
  try{
    const result=await call('createWholesaleOrderRequest',{commandId:state.orderCommandId,branchId,items:state.cart});
    if(!result?.ok || !result?.requestId)throw new Error('Order not acknowledged');
    // The server acknowledged an immutable request. From this point forward,
    // cart cleanup and history refresh must never report order submission failure
    // or cause a second request with a fresh command ID.
    state.orderCommandId=null;
    state.cart=[];
    $('cartCount').textContent='0';
    closeDrawer();
    toast(phrase('requestSent'));
    try { await persistBuyer([],state.saved); }
    catch (cleanupError) {
      console.warn('Request accepted, but cart cleanup needs retry',cleanupError?.code);
    }
    await openDrawer('orders');
  }catch(error){console.warn('Wholesale order request rejected',error?.code||error?.message);toast(phrase('requestFailed'));}
  finally{state.submitting=false;renderDrawer();}
}
$('searchInput')?.addEventListener('input', event => {
  state.query = event.target.value.trim();
  const clearBtn = $('searchClearBtn');
  if (clearBtn) clearBtn.hidden = !event.target.value.length;
  renderCatalog();
});

$('searchClearBtn')?.addEventListener('click', () => {
  const input = $('searchInput');
  if (input) {
    input.value = '';
    state.query = '';
    $('searchClearBtn').hidden = true;
    input.focus();
    renderCatalog();
  }
});

$('sortTriggerBtn')?.addEventListener('click', event => {
  event.stopPropagation();
  const menu = $('sortMenu');
  const btn = $('sortTriggerBtn');
  if (!menu) return;
  const willOpen = menu.hidden;
  menu.hidden = !willOpen;
  btn.setAttribute('aria-expanded', String(willOpen));
});

document.addEventListener('click', event => {
  const capsule = $('sortCapsule');
  const menu = $('sortMenu');
  const btn = $('sortTriggerBtn');
  if (capsule && !capsule.contains(event.target)) {
    if (menu) menu.hidden = true;
    if (btn) btn.setAttribute('aria-expanded', 'false');
  }
});

document.querySelectorAll('.sort-option').forEach(opt => {
  opt.addEventListener('click', event => {
    event.stopPropagation();
    const val = opt.dataset.value;
    if (val) setSort(val);
  });
});

window.addEventListener('keydown', event => {
  if (event.key === '/' && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName)) {
    event.preventDefault();
    const input = $('searchInput');
    if (input) {
      input.focus();
      input.select();
    }
  }
  if (event.key === 'Escape') {
    const menu = $('sortMenu');
    const btn = $('sortTriggerBtn');
    if (menu && !menu.hidden) {
      menu.hidden = true;
      if (btn) btn.setAttribute('aria-expanded', 'false');
    }
  }
});
$('languageBtn').addEventListener('click',()=>{state.lang=state.lang==='ar'?'en':'ar';applyLanguage();});
$('loadMoreBtn').addEventListener('click',()=>loadCatalog());
$('productGrid').addEventListener('click',event=>{
  const save=event.target.closest('[data-save]');
  if(save){requireBuyer(protectedIntent('save',{productId:save.dataset.save}));return;}

  const quickAdd=event.target.closest('[data-quick-add]');
  if(quickAdd){
    const productId=quickAdd.dataset.quickAdd;
    const groupId=quickAdd.dataset.groupId;
    const p=getProduct(productId);
    if(!p)return;
    const g=p.groups.find(x=>x.id===groupId)||p.groups[0];
    if(!g)return;
    requireBuyer(protectedIntent('add',{productId,groupId:g.id,quantity:1}));
    return;
  }

  const stepAdd=event.target.closest('[data-stepper-add]');
  if(stepAdd){
    const productId=stepAdd.dataset.stepperAdd;
    const p=getProduct(productId);
    if(!p)return;
    const existing=state.cart.find(c=>c.productId===productId);
    const groupId=existing?existing.groupId:(p.groups.find(g=>g.defaultForWholesale)||p.groups[0]).id;
    requireBuyer(protectedIntent('add',{productId,groupId,quantity:1}));
    return;
  }

  const stepSub=event.target.closest('[data-stepper-sub]');
  if(stepSub){
    const productId=stepSub.dataset.stepperSub;
    if(!state.user){goAuth(protectedIntent('cart'));return;}
    const cart=state.cart.map(line=>({...line}));
    let targetIndex=-1;
    for(let i=cart.length-1;i>=0;i--){
      if(cart[i].productId===productId){targetIndex=i;break;}
    }
    if(targetIndex>=0){
      cart[targetIndex].quantity-=1;
      if(cart[targetIndex].quantity<=0)cart.splice(targetIndex,1);
      stepSub.disabled=true;
      persistBuyer(cart,state.saved).catch(()=>{
        stepSub.disabled=false;
        toast(phrase('saveFailed'));
      });
    }
    return;
  }

  const open=event.target.closest('[data-open]');
  if(open)productDetails(open.dataset.open);
});
$('cartBtn').addEventListener('click',()=>requireBuyer(protectedIntent('cart')));
$('savedBtn').addEventListener('click',()=>{if(state.user)openDrawer('saved');else goAuth(protectedIntent('saved'));});
$('ordersNav').addEventListener('click',()=>requireBuyer(protectedIntent('orders')));
$('closeProduct').addEventListener('click',()=>$('productDialog').close());
$('closeDrawer').addEventListener('click',closeDrawer);
$('drawerScrim').addEventListener('click',closeDrawer);
$('closeAuth').addEventListener('click',()=>{state.pending=null;state.phoneConfirmation=null;$('authDialog').close();});
$('accountBtn').addEventListener('click',()=>{
  if(!state.user)return goAuth(protectedIntent('cart'));
  if(confirm(state.lang==='ar'?'هل تريد تسجيل الخروج؟':'Sign out of your account?')){
    closeDrawer();state.cart=[];state.saved=[];state.pending=null;
    state.backend?.signOut(state.backend.auth).catch(()=>toast(phrase('sessionFailed')));
  }
});
$('methodEmailTab').addEventListener('click',()=>setAuthMethod('email'));
$('methodPhoneTab').addEventListener('click',()=>setAuthMethod('phone'));
$('googleAuthBtn').addEventListener('click',async()=>{
  if(!state.backend){$('authError').textContent=phrase('unavailableText');$('authError').hidden=false;return;}
  const button=$('googleAuthBtn');button.disabled=true;
  $('authError').hidden=true;
  const isMobile=/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
  try{
    const provider=new state.backend.GoogleAuthProvider();
    provider.setCustomParameters({prompt:'select_account'});
    if(isMobile && state.backend.signInWithRedirect){
      await state.backend.signInWithRedirect(state.backend.auth,provider);
      return;
    }
    await state.backend.signInWithPopup(state.backend.auth,provider);
  }catch(error){
    console.warn('Google sign-in error:',error?.code,error?.message);
    if(error?.code==='auth/popup-closed-by-user'||error?.code==='auth/cancelled-popup-request'||error?.code==='auth/popup-blocked'){
      if(state.backend.signInWithRedirect){
        try{
          const provider=new state.backend.GoogleAuthProvider();
          provider.setCustomParameters({prompt:'select_account'});
          await state.backend.signInWithRedirect(state.backend.auth,provider);
          return;
        }catch(redirectErr){
          console.warn('Google redirect fallback error:',redirectErr?.code,redirectErr?.message);
        }
      }
    }
    const errStr = String(error?.message || '') + ' ' + String(error?.code || '');
    if (errStr.includes('requests-from-referer') || error?.code === 'auth/unauthorized-domain') {
      $('authError').textContent = state.lang === 'ar'
        ? 'نطاق الموقع غير مضاف إلى نطاقات Google Auth في Firebase Console.'
        : 'Domain is blocked by Google Auth referrers. Please check authorized domains.';
    } else {
      $('authError').textContent = (error?.message || phrase('authFailed')) + (error?.code ? ` (${error.code})` : '');
    }
    $('authError').hidden=false;
  }finally{button.disabled=false;}
});
$('appleAuthBtn')?.addEventListener('click',async()=>{
  if(!state.backend){$('authError').textContent=phrase('unavailableText');$('authError').hidden=false;return;}
  const button=$('appleAuthBtn');button.disabled=true;
  $('authError').hidden=true;
  const isMobile=/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
  try{
    const provider=new state.backend.OAuthProvider('apple.com');
    provider.addScope('email');
    provider.addScope('name');
    if(isMobile && state.backend.signInWithRedirect){
      await state.backend.signInWithRedirect(state.backend.auth,provider);
      return;
    }
    await state.backend.signInWithPopup(state.backend.auth,provider);
  }catch(error){
    console.warn('Apple sign-in error:',error?.code,error?.message);
    if(error?.code==='auth/popup-closed-by-user'||error?.code==='auth/cancelled-popup-request'||error?.code==='auth/popup-blocked'){
      if(state.backend.signInWithRedirect){
        try{
          const provider=new state.backend.OAuthProvider('apple.com');
          provider.addScope('email');
          provider.addScope('name');
          await state.backend.signInWithRedirect(state.backend.auth,provider);
          return;
        }catch(redirectErr){
          console.warn('Apple redirect fallback error:',redirectErr?.code,redirectErr?.message);
        }
      }
    }
    $('authError').textContent = (error?.message || phrase('authFailed')) + (error?.code ? ` (${error.code})` : '');
    $('authError').hidden=false;
  }finally{button.disabled=false;}
});
$('phoneInputForm').addEventListener('submit',async event=>{
  event.preventDefault();
  if(!state.backend){$('authError').textContent=phrase('unavailableText');$('authError').hidden=false;return;}
  const button=$('sendPhoneCodeBtn');button.disabled=true;button.textContent=phrase('processing');
  $('authError').hidden=true;
  try{
    const phone=normalizePhoneNumber($('phoneInput').value);
    state.lastPhone=phone;
    if(!state.recaptchaVerifier){
      state.recaptchaVerifier=new state.backend.RecaptchaVerifier(state.backend.auth,'phoneRecaptcha',{
        size:'invisible',
        callback:()=>{},
        'expired-callback':()=>{
          if(state.recaptchaVerifier){try{state.recaptchaVerifier.clear();}catch{}}
          state.recaptchaVerifier=null;
        }
      });
    }
    const confirmation=await state.backend.signInWithPhoneNumber(state.backend.auth,phone,state.recaptchaVerifier);
    state.phoneConfirmation=confirmation;
    setPhoneStep('code');
  }catch(error){
    console.warn('Phone sign-in request failed:',error?.code,error?.message);
    if(state.recaptchaVerifier){try{state.recaptchaVerifier.clear();}catch{}}
    state.recaptchaVerifier=null;
    if(error?.message==='Invalid phone format'||error?.code==='auth/invalid-phone-number'){
      $('authError').textContent=phrase('invalidPhone');
    }else if(error?.code==='auth/quota-exceeded'||error?.code==='auth/too-many-requests'){
      $('authError').textContent=phrase('phoneQuota');
    }else{
      $('authError').textContent = (error?.message || phrase('authFailed')) + (error?.code ? ` (${error.code})` : '');
    }
    $('authError').hidden=false;
  }finally{button.disabled=false;button.textContent=phrase('sendCode');}
});
$('phoneCodeForm').addEventListener('submit',async event=>{
  event.preventDefault();
  if(!state.phoneConfirmation){setPhoneStep('input');return;}
  const button=$('verifyPhoneCodeBtn');button.disabled=true;button.textContent=phrase('processing');
  $('authError').hidden=true;
  try{
    const code=$('phoneCodeInput').value.trim();
    if(!/^\d{6}$/.test(code))throw new Error('invalid-code');
    await state.phoneConfirmation.confirm(code);
  }catch(error){
    console.warn('Phone OTP verification failed:',error?.code,error?.message);
    if(error?.code==='auth/invalid-verification-code'||error?.message==='invalid-code'||error?.code==='auth/code-expired'){
      $('authError').textContent=phrase('invalidCode');
    }else{
      $('authError').textContent = (error?.message || phrase('authFailed')) + (error?.code ? ` (${error.code})` : '');
    }
    $('authError').hidden=false;
  }finally{button.disabled=false;button.textContent=phrase('verifyCode');}
});
$('changePhoneBtn').addEventListener('click',()=>setPhoneStep('input'));
$('resendPhoneCodeBtn').addEventListener('click',async()=>{
  if(!state.lastPhone||!state.backend)return;
  const button=$('resendPhoneCodeBtn');button.disabled=true;
  try{
    if(!state.recaptchaVerifier){
      state.recaptchaVerifier=new state.backend.RecaptchaVerifier(state.backend.auth,'phoneRecaptcha',{size:'invisible'});
    }
    const confirmation=await state.backend.signInWithPhoneNumber(state.backend.auth,state.lastPhone,state.recaptchaVerifier);
    state.phoneConfirmation=confirmation;
    toast(phrase('codeResent'));
  }catch(error){
    console.warn('Resend failed:',error?.code);
    $('authError').textContent=phrase('authFailed');$('authError').hidden=false;
  }finally{setTimeout(()=>{button.disabled=false;},6000);}
});
$('loginTab').addEventListener('click',()=>{state.authMode='login';updateAuthTabs();});
$('registerTab').addEventListener('click',()=>{state.authMode='register';updateAuthTabs();});
$('authForm').addEventListener('submit',async event=>{
  event.preventDefault();
  if(!state.backend){$('authError').textContent=phrase('unavailableText');$('authError').hidden=false;return;}
  const button=$('submitAuth');button.disabled=true;button.textContent=phrase('processing');
  $('authError').hidden=true;
  try{
    const email=$('emailInput').value.trim();const password=$('passwordInput').value;
    const f=state.authMode==='login'?state.backend.signInWithEmailAndPassword:state.backend.createUserWithEmailAndPassword;
    await f(state.backend.auth,email,password);
    $('passwordInput').value='';
  }catch(error){console.warn('Buyer login rejected:',error?.code);$('authError').textContent=phrase('authFailed');$('authError').hidden=false;}
  finally{button.disabled=false;button.textContent=phrase('continue');}
});
$('drawerContent').addEventListener('click',async event=>{
  const view=event.target.closest('[data-view]');
  if(view){const p=getProduct(view.dataset.view);if(p){closeDrawer();productDetails(p.id);}else toast(phrase('comingSoon'));return;}
  const cancel=event.target.closest('[data-cancel]');
  if(cancel){
    if(!state.user||!window.confirm(phrase('cancelConfirm')))return;
    cancel.disabled=true;
    try{
      const response=await call('cancelMyWholesaleRequest',{requestId:cancel.dataset.cancel});
      if(!response?.ok)throw new Error('Cancellation not acknowledged');
      toast(phrase('cancelSuccess'));await openDrawer('orders');
    }catch(err){console.warn('Cancellation failed',err?.code||err?.message);toast(phrase('requestFailed'));cancel.disabled=false;}
    return;
  }
  const change=event.target.closest('[data-adjust]');
  if(change){
    const [index,delta]=change.dataset.adjust.split(':').map(Number);
    if(!Number.isSafeInteger(index)||!Number.isSafeInteger(delta))return;
    const cart=state.cart.map(line=>({...line}));
    if(!cart[index])return;
    cart[index].quantity+=delta;
    if(cart[index].quantity<=0)cart.splice(index,1);
    else if(cart[index].quantity>10000){toast(phrase('requestFailed'));return;}
    change.disabled=true;
    try{await persistBuyer(cart,state.saved);}
    catch(err){change.disabled=false;toast(phrase('saveFailed'));}
    return;
  }
  const node=event.target.closest('[data-remove]');if(!node)return;
  const [mode,indexText]=node.dataset.remove.split(':');const index=Number(indexText);
  try{
    if(mode==='cart')await persistBuyer(state.cart.filter((_,i)=>i!==index),state.saved);
    else await persistBuyer(state.cart,state.saved.filter((_,i)=>i!==index));
    toast(phrase('removed'));
  }catch{toast(phrase('saveFailed'));}
});
$('themeToggleBtn')?.addEventListener('click', toggleTheme);
$('wsElevatorBtn')?.addEventListener('click', () => {
  window.scrollTo({ top: 0, behavior: 'smooth' });
});
$('wsFooterCartBtn')?.addEventListener('click', () => $('cartBtn')?.click());
$('wsFooterOrdersBtn')?.addEventListener('click', () => $('ordersNav')?.click());
$('wsFooterAccountBtn')?.addEventListener('click', () => $('accountBtn')?.click());
$('wsFooterLangAr')?.addEventListener('click', () => {
  if (state.lang !== 'ar') { state.lang = 'ar'; applyLanguage(); }
});
$('wsFooterLangEn')?.addEventListener('click', () => {
  if (state.lang !== 'en') { state.lang = 'en'; applyLanguage(); }
});
initTheme();
applyLanguage();
setInterval(updateWsFooterClock, 20000);
(async()=>{try{await connectBackend();await loadCatalog(true);}catch(error){console.warn('Storefront startup:',error?.message);state.loadError=true;state.loading=false;renderCatalog();}})();
