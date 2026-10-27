
import { protectedIntent, mergeCart, normalizeCatalogItem } from './state.js';
import {icon, readPreference, writePreference, defaultGroup, cartSummary, quantityQuote} from './ui.js';

const $ = (id) => document.getElementById(id);
const t = {
  ar: {
    howItWorks:'كيف تطلب؟',mainNav:'التنقل الرئيسي',stepBrowse:'تصفّح على راحتك',stepBrowseHint:'اكتشف المجموعة دون تسجيل.',
    stepPack:'عبوتك. كميتك.',stepPackHint:'سعر واضح لكل وحدة بيع.',stepReview:'نراجع طلبك معك',stepReviewHint:'أرسل طلبك ليراجعه فريقنا.',
    deskTitle:'طلبك القادم',deskGuest:'مساحة خاصة لتجارتك. احفظ المنتجات، كوّن سلتك، وتابع طلباتك من مكان واحد.',deskEmpty:'ابدأ بمنتج من المجموعة. سنجمع عبواتك هنا.',
    deskNote:'طلبك يُراجع أولاً. لا يتم تحصيل أي دفعة هنا.',reviewCart:'راجع السلة',packs:'عبوة',choosePack:'اختر العبوة',inStock:'متاح للطلب',
    clearSearch:'مسح البحث',sortLabel:'ترتيب المنتجات',viewLabel:'طريقة عرض المنتجات',gridView:'عرض البطاقات',listView:'عرض مكثف',categories:'فئات المنتجات',
    closePanel:'إغلاق اللوحة',closeDetails:'إغلاق التفاصيل',closeAuth:'إغلاق تسجيل الدخول',clearFilters:'إعادة ضبط التصفية',browse:'تصفح المنتجات',
    noImage:'الصورة غير متوفرة',partialPrice:'تُراجع الأسعار عند إرسال الطلب',totalUnits:'إجمالي القطع',invalidQuantity:'أدخل عدداً صحيحاً من ١ إلى ١٠٠٠٠.',
    pending_review:'بانتظار المراجعة',accepted_for_processing:'جاهز للمعالجة',rejected:'مرفوض',cancelled_by_customer:'ملغي من العميل',
    reviewNote:'نراجع الأسعار والتوفر قبل تأكيد الطلب.',saveRemoved:'تمت إزالة المنتج من المحفوظات',

    top:'بوابة الأعمال من Pure Pets',wholesale:'تجربة مخصصة لطلبات الجملة',navCatalog:'المنتجات',navOrders:'طلباتي',
    cart:'السلة',login:'دخول / تسجيل',logout:'تسجيل الخروج',eyebrow:'PURE PETS / BUSINESS',heroOne:'رعاية لهم.',heroTwo:'ونموّ لتجارتك.',
    heroDesc:'منتجات مختارة بعناية، وعبوات تناسب تجارتك. ابدأ طلبك بالجملة بخطوات واضحة.',explore:'اكتشف المنتجات',
    guestHint:'تصفح بحرية. سجّل دخولك فقط عند اتخاذ إجراء.',collection:'THE COLLECTION / المجموعة',catalogHeading:'مساحة شراء، على مقاسك.',
    catalogHint:'اختر المنتج، حدّد العبوة، وأرسل طلبك للمراجعة.',products:'منتج',search:'ابحث عن المنتجات...',
    sortFeatured:'الترتيب الافتراضي',sortLow:'الأقل سعراً',sortHigh:'الأعلى سعراً',loadMore:'عرض المزيد',
    promiseOne:'وحدات بيع واضحة',promiseTwo:'أسعار جملة موثقة',promiseThree:'طلبات مرتبطة بحسابك',footerCopy:'رعاية أفضل. تجارة أقوى.',
    workspace:'مساحة مشتري الجملة',authTitle:'أهلاً بتجارتك.',authIntro:'أكمل تسجيل الدخول للمتابعة من حيث توقفت.',
    loginTab:'تسجيل الدخول',registerTab:'إنشاء حساب',email:'البريد الإلكتروني',password:'كلمة المرور',continue:'متابعة',
    all:'الكل',emptyTitle:'لا توجد منتجات مطابقة',emptyText:'غيّر كلمة البحث أو التصفية وحاول مرة أخرى.',
    unavailableTitle:'المتجر غير جاهز حالياً',unavailableText:'تعذر الوصول إلى المنتجات الآن. أعد المحاولة بعد قليل؛ محفوظاتك وطلباتك تبقى مرتبطة بحسابك.',
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
    units:'قطعة',verified:'سعر الجملة',noBranch:'اختر الفرع',cancelRequest:'إلغاء الطلب',cancelConfirm:'هل تريد إلغاء طلب الجملة المعلق؟',cancelSuccess:'تم إلغاء الطلب',increase:'زيادة الكمية',decrease:'تقليل الكمية'
  },
  en: {
    howItWorks:'How to order',mainNav:'Main navigation',stepBrowse:'Explore at your pace',stepBrowseHint:'Browse the collection without signing in.',
    stepPack:'Your pack. Your quantity.',stepPackHint:'Clear pricing for every selling unit.',stepReview:'A team behind your order',stepReviewHint:'Send your request for our team to review.',
    deskTitle:'Your next order',deskGuest:'A space for your business. Save your essentials, build your cart and follow every request.',deskEmpty:'Start with something from the collection. Your packs will come together here.',
    deskNote:'Every request is reviewed first. No payment is collected here.',reviewCart:'Review cart',packs:'packs',choosePack:'Choose pack',inStock:'Available to request',
    clearSearch:'Clear search',sortLabel:'Sort products',viewLabel:'Product view',gridView:'Card view',listView:'Compact view',categories:'Product categories',
    closePanel:'Close panel',closeDetails:'Close details',closeAuth:'Close sign in',clearFilters:'Reset filters',browse:'Browse products',
    noImage:'Image unavailable',partialPrice:'Pricing checked on submission',totalUnits:'Total units',invalidQuantity:'Enter a whole number from 1 to 10,000.',
    pending_review:'Pending review',accepted_for_processing:'Ready to process',rejected:'Rejected',cancelled_by_customer:'Cancelled by customer',
    reviewNote:'We review pricing and availability before confirming your request.',saveRemoved:'Removed from saved products',

    top:'The Pure Pets business gateway',wholesale:'A dedicated wholesale experience',navCatalog:'Products',navOrders:'My orders',
    cart:'Cart',login:'Sign in / Join',logout:'Sign out',eyebrow:'PURE PETS / BUSINESS',heroOne:'Better care.',heroTwo:'Stronger business.',
    heroDesc:'Thoughtfully chosen products. Packs that work for you. A simpler way to buy for the pets you care for.',explore:'Explore the collection',
    guestHint:'Browse freely. Sign in only when you want to take action.',collection:'THE COLLECTION / WHOLESALE',catalogHeading:'Your next order starts here.',
    catalogHint:'Find your essentials. Choose your pack. Request your order.',products:'products',search:'Search products...',
    sortFeatured:'Featured first',sortLow:'Price: low to high',sortHigh:'Price: high to low',loadMore:'Load more',
    promiseOne:'Clear wholesale units',promiseTwo:'Verified pack pricing',promiseThree:'Orders tied to your account',footerCopy:'Better care. Stronger business.',
    workspace:'Your wholesale workspace',authTitle:'Welcome to your next chapter.',authIntro:'Sign in to continue right where you left off.',
    loginTab:'Sign in',registerTab:'Create account',email:'Email address',password:'Password',continue:'Continue',
    all:'All',emptyTitle:'No matching products',emptyText:'Try a different search or category.',
    unavailableTitle:'Catalog temporarily unavailable',unavailableText:'We cannot reach the collection right now. Please try again shortly. Your saved items and requests stay with your account.',
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
    units:'units',verified:'Wholesale price',noBranch:'Select branch',cancelRequest:'Cancel request',cancelConfirm:'Cancel this pending wholesale request?',cancelSuccess:'Request cancelled',increase:'Increase quantity',decrease:'Decrease quantity'
  }
};
const state = {
  lang: readPreference('language','ar')==='en'?'en':'ar', view:readPreference('view','grid')==='list'?'list':'grid', buyerBusy:false, session:0, products: [], cursor:null, categories:[], category:'all', query:'', sort:'featured',
  branches:[], cart:[], saved:[], user:null, backend:null, pending:null, activeProduct:null,
  authMode:'login', drawer:'cart', loadError:false, authReady:false, loading:false,
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
  writePreference('language',state.lang);
  document.documentElement.lang=state.lang;
  document.documentElement.dir=state.lang==='ar'?'rtl':'ltr';
  document.querySelectorAll('[data-t]').forEach(node=>{
    const key=node.dataset.t;
    if(Object.hasOwn(t[state.lang],key))node.textContent=phrase(key);
  });
  document.querySelectorAll('[data-placeholder]').forEach(node=>node.placeholder=phrase(node.dataset.placeholder));
  document.querySelectorAll('[data-aria]').forEach(node=>node.setAttribute('aria-label',phrase(node.dataset.aria)));
  $('languageBtn').textContent=state.lang==='ar'?'EN':'عربي';
  $('languageBtn').setAttribute('aria-label',state.lang==='ar'?'Switch to English':'التبديل إلى العربية');
  $('accountBtn').textContent=state.user ? phrase('welcome') : phrase('login');
  document.title=state.lang==='ar'?'Pure Pets | طلبات الجملة':'Pure Pets | Wholesale ordering';
  renderCatalog(); renderDrawer(); updateAuthTabs();
}
function goAuth(intent) {
  if (state.user) return runIntent(intent);
  state.pending=intent;
  state.authMode='login';
  updateAuthTabs();
  $('authError').hidden=true;
  if(!$('authDialog').open)$('authDialog').showModal();
  $('emailInput').focus();
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
  const config=await fetch('/ws/api/config',{cache:'no-store'}).then(async res=>{
    if(!res.ok)throw new Error('Missing Firebase storefront configuration');
    return res.json();
  });
  if(!config.appCheckSiteKey)throw new Error('Missing Firebase App Check site key');
  const [{initializeApp},{getAuth,onAuthStateChanged,signInWithEmailAndPassword,createUserWithEmailAndPassword,signOut},{getFunctions,httpsCallable},{initializeAppCheck,ReCaptchaV3Provider}]
  = await Promise.all([
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-functions.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app-check.js')
  ]);
  const app=initializeApp(config.firebase,'pure-pets-wholesale');
  if(!config.appCheckSiteKey)throw new Error('Missing Firebase App Check site key');
  initializeAppCheck(app,{provider:new ReCaptchaV3Provider(config.appCheckSiteKey),isTokenAutoRefreshEnabled:true});
  const auth=getAuth(app);
  const functions=getFunctions(app,config.region||'us-central1');
  state.backend={
    auth,signInWithEmailAndPassword,createUserWithEmailAndPassword,signOut,
    invoke:async(name,payload)=> (await httpsCallable(functions,name,{timeout:25000})(payload)).data
  };
  onAuthStateChanged(auth, async (user)=>{
    const session=++state.session;
    state.user=user||null; state.authReady=true; state.cart=[];state.saved=[];state.orders=[];state.orderCommandId=null;
    $('accountBtn').textContent=user?phrase('welcome'):phrase('login');
    if(user) {
      try {
        const record=await call('getWholesaleBuyerState');
        if(session!==state.session)return;
        state.cart=Array.isArray(record.cart)?record.cart:[];
        state.saved=Array.isArray(record.saved)?record.saved:[];
      } catch (error) { toast(phrase('saveFailed')); }
    }
    if(session!==state.session)return;
    $('cartCount').textContent=String(state.cart.reduce((sum,line)=>sum+(Number(line.quantity)||0),0));
    renderDrawer();renderCatalog();
    if(user && state.pending) {
      const intent=state.pending;state.pending=null;
      $('authDialog').close();
      try {await runIntent(intent);} catch(e){toast(e.message||phrase('saveFailed'));}
    }
  });
}
async function loadCatalog(reset=false) {
  if (state.loading) return;
  state.loading=true;state.loadError=false;
  $('catalogStatus').textContent=phrase('starting');
  if(reset){state.cursor=null;state.products=[];}
  renderCatalog();
  try {
    if(!state.backend)await connectBackend();
    const result=await call('listWholesaleCatalog',{cursor:state.cursor,limit:24});
    const products=(Array.isArray(result.items)?result.items:[]).map(normalizeCatalogItem).filter(Boolean);
    const existing=new Map(state.products.map(item=>[item.id,item]));
    products.forEach(item=>existing.set(item.id,item));
    state.products=[...existing.values()];
    state.cursor=typeof result.nextCursor==='string'&&result.nextCursor?result.nextCursor:null;
    state.branches=Array.isArray(result.branches)?result.branches.filter(b=>b&&typeof b.id==='string'&&b.active===true):[];
  }catch(error){state.loadError=true;console.warn('Wholesale catalog unavailable:',error?.code||error?.message);}
  state.loading=false;
  $('catalogStatus').textContent='';
  renderCatalog();
}
function categoryTitle(category) {
  if(category==='all')return phrase('all');
  const known={food:{ar:'الأغذية',en:'Food'},accessories:{ar:'الإكسسوارات',en:'Accessories'},birds:{ar:'الطيور',en:'Birds'},dogs:{ar:'الكلاب',en:'Dogs'},cats:{ar:'القطط',en:'Cats'}};
  return known[category]?(known[category][state.lang]):category;
}
function visibleProducts() {
  let products=state.products.filter(p=>(state.category==='all'||p.category===state.category)
    && (p.nameAr+' '+p.nameEn+' '+p.id+' '+p.category+' '+categoryTitle(p.category)).toLocaleLowerCase().includes(state.query.toLocaleLowerCase()));
  if(state.sort!=='featured') products=[...products].sort((a,b)=>(defaultGroup(a).priceMinor-defaultGroup(b).priceMinor) *(state.sort==='priceDesc'?-1:1));
  return products;
}
function renderCatalog() {
  const focus=document.activeElement;
  const focusedCategory=focus?.dataset.category, focusedSaved=focus?.dataset.save;
  const tabs=$('categoryTabs');tabs.replaceChildren();
  const categories=['all',...new Set(state.products.map(p=>p.category))];
  if(!categories.includes(state.category))state.category='all';
  categories.forEach(category=>{
    const b=document.createElement('button');b.type='button';b.className='category-pill'+(category===state.category?' active':'');
    b.dataset.category=category;b.setAttribute('aria-pressed',String(category===state.category));
    b.innerHTML=esc(categoryTitle(category))+'<small>'+String(category==='all'?state.products.length:state.products.filter(p=>p.category===category).length)+'</small>';
    b.addEventListener('click',()=>{state.category=category;renderCatalog();});tabs.append(b);
  });
  if(focusedCategory)Array.from(tabs.children).find(b=>b.dataset.category===focusedCategory)?.focus({preventScroll:true});
  $('clearSearch').hidden=!state.query;
  $('gridView').setAttribute('aria-pressed',String(state.view==='grid'));
  $('listView').setAttribute('aria-pressed',String(state.view==='list'));
  const list=visibleProducts();
  $('productCount').textContent=state.loadError&&!state.products.length?'—':String(list.length);
  const grid=$('productGrid');grid.classList.toggle('list-view',state.view==='list');grid.setAttribute('aria-busy',String(state.loading));grid.replaceChildren();
  $('loadMoreBtn').hidden=!state.cursor||state.loading;
  $('catalogStatus').replaceChildren();
  if(state.loading)$('catalogStatus').textContent=phrase('starting');
  else if(state.loadError&&state.products.length){
    $('catalogStatus').append(document.createTextNode(phrase('unavailableTitle')));
    const retry=document.createElement('button');retry.type='button';retry.textContent=phrase('retry');retry.addEventListener('click',()=>loadCatalog());$('catalogStatus').append(retry);
  } else if(state.products.length) $('catalogStatus').textContent=String(list.length)+' '+phrase('products');
  renderDesk();
  if(state.loading&&!state.products.length){
    for(let i=0;i<6;i++){const node=document.createElement('div');node.className='loading-card';node.setAttribute('aria-hidden','true');grid.append(node);}return;
  }
  if(!list.length){
    const el=document.createElement('div');el.className='empty-state';
    el.innerHTML=icon(state.loadError?'warning-circle':'magnifying-glass')+'<strong>'+esc(phrase(state.loadError?'unavailableTitle':'emptyTitle'))+'</strong><p>'+esc(state.loadError?phrase('unavailableText'):(state.products.length?phrase('emptyText'):phrase('noProducts')))+'</p>';
    if(state.loadError||state.query||state.category!=='all'){
      const b=document.createElement('button');b.type='button';b.className='secondary-button';b.textContent=phrase(state.loadError?'retry':'clearFilters');
      b.addEventListener('click',()=>{if(state.loadError)loadCatalog(true);else resetFilters();});el.append(b);
    }
    grid.append(el);return;
  }
  for(const item of list){
    const group=defaultGroup(item),saved=state.saved.includes(item.id);
    const art=item.image?'<img src="'+esc(item.image)+'" loading="lazy" decoding="async" alt="">':placeholder();
    const card=document.createElement('article');card.className='product-card';
    card.innerHTML='<button class="product-art" type="button" data-open="'+esc(item.id)+'" aria-label="'+esc(localized(item))+'">'+art+'</button>'+
      '<div class="card-body"><div class="card-meta"><span class="card-type">'+esc(categoryTitle(item.category))+'</span><button type="button" class="save-float" data-save="'+esc(item.id)+'" aria-pressed="'+saved+'" aria-label="'+esc(phrase(saved?'remove':'save')+' · '+localized(item))+'" '+(state.buyerBusy?'disabled':'')+'>'+icon('heart')+'</button></div>'+
      '<button class="card-title" type="button" data-open="'+esc(item.id)+'"><h3>'+esc(localized(item))+'</h3></button><p class="card-pack">'+esc(localized(group))+' · '+esc(group.unitsPerGroup)+' '+esc(phrase('units'))+'</p>'+
      '<div class="card-bottom"><div><span class="price-label">'+esc(phrase('perPack'))+'</span><div class="price-value">'+esc(money(group.priceMinor,item.currency))+'</div></div></div>'+
      '<button class="choose-pack" type="button" data-open="'+esc(item.id)+'" '+(item.available>0?'':'disabled')+'><span>'+esc(phrase(item.available>0?'choosePack':'soldOut'))+'</span>'+icon('arrow-right','directional')+'</button></div>';
    grid.append(card);
  }
  if(focusedSaved)Array.from(grid.querySelectorAll('[data-save]')).find(b=>b.dataset.save===focusedSaved)?.focus({preventScroll:true});
}
function placeholder(){return '<span class="placeholder-art">'+icon('package')+'<span>'+esc(phrase('noImage'))+'</span></span>';}
function resetFilters(){state.query='';state.category='all';state.sort='featured';$('searchInput').value='';$('sortSelect').value='featured';renderCatalog();$('searchInput').focus({preventScroll:true});}
function summaryText(summary){return summary.incomplete?phrase('partialPrice'):summary.totals.map(v=>money(v.minor,v.currency)).join(' · ');}
function renderDesk(){
  const summary=cartSummary(state.cart,state.products),hasCart=!!state.user&&state.cart.length>0;
  $('cartCount').textContent=String(summary.packs);
  $('orderDock').hidden=!hasCart;$('dockCount').textContent=String(summary.packs);$('dockTotal').textContent=summaryText(summary);
  $('deskContent').innerHTML=hasCart?'<div class="desk-stat">'+summary.packs+'<small>'+esc(phrase('packs'))+'</small></div><span class="desk-total">'+esc(summaryText(summary))+'</span><button class="primary-button" type="button" data-desk="cart">'+esc(phrase('reviewCart'))+icon('arrow-right','directional')+'</button>':
    '<div class="desk-art" aria-hidden="true">'+icon('package')+'</div><p class="desk-empty">'+esc(phrase(state.user?'deskEmpty':'deskGuest'))+'</p><button class="primary-button" type="button" data-desk="cart">'+esc(phrase(state.user?'reviewCart':'login'))+'</button>';
  $('deskContent').insertAdjacentHTML('beforeend','<button class="text-button desk-link" type="button" data-desk="orders">'+esc(phrase('ordersHeading'))+'</button>');
}
function getProduct(id){return state.products.find(p=>p.id===id);}
function productDetails(id){
  const product=getProduct(id);if(!product)return;
  state.activeProduct=id;
  const art=product.image?'<img src="'+esc(product.image)+'" alt="'+esc(localized(product))+'">':placeholder();
  const dialog=$('productDialog');
  $('productDetail').innerHTML='<div class="detail-layout"><div class="detail-image">'+art+'</div><div class="detail-info"><span class="detail-category">'+esc(categoryTitle(product.category))+'</span><h2 id="detailTitle">'+esc(localized(product))+'</h2>'+
    '<label>'+esc(phrase('selectPack'))+'<select id="detailGroup">'+product.groups.map(g=>'<option value="'+esc(g.id)+'">'+esc(localized(g))+' · '+esc(g.unitsPerGroup)+' '+esc(phrase('units'))+' · '+esc(money(g.priceMinor,product.currency))+'</option>').join('')+'</select></label>'+
    '<div class="quantity-row"><label for="detailQuantity">'+esc(phrase('quantity'))+'</label><div class="quantity-stepper"><button id="detailDecrease" type="button" aria-label="'+esc(phrase('decrease'))+'">'+icon('minus')+'</button><input id="detailQuantity" type="number" min="1" max="10000" step="1" value="1" inputmode="numeric"><button id="detailIncrease" type="button" aria-label="'+esc(phrase('increase'))+'">'+icon('plus')+'</button></div></div>'+
    '<div id="detailQuote" class="detail-quote" aria-live="polite"></div><button class="primary-button" id="detailAdd" type="button">'+icon('shopping-bag')+'<span>'+esc(phrase(product.available>0?'add':'soldOut'))+'</span></button><p class="notice">'+esc(phrase('reviewNote'))+'</p></div></div>';
  $('detailGroup').value=defaultGroup(product).id;
  const update=()=>{
    const quantity=Number($('detailQuantity').value),quote=quantityQuote(product,$('detailGroup').value,quantity);
    $('detailDecrease').disabled=!quote||quantity<=1;$('detailIncrease').disabled=!quote||quantity>=10000;
    $('detailQuantity').setAttribute('aria-invalid',String(!quote));
    $('detailAdd').disabled=!quote||product.available<=0||state.buyerBusy;
    $('detailQuote').innerHTML=quote?'<div><small>'+esc(phrase('total'))+'</small><strong>'+esc(money(quote.minor,quote.currency))+'</strong></div><span class="unit-total">'+quote.units+' '+esc(phrase('units'))+'</span>':'<span class="error-line">'+esc(phrase('invalidQuantity'))+'</span>';
  };
  $('detailGroup').addEventListener('change',update);$('detailQuantity').addEventListener('input',update);
  for(const [id,delta] of [['detailDecrease',-1],['detailIncrease',1]])$(id).addEventListener('click',()=>{$('detailQuantity').value=String(Number($('detailQuantity').value)+delta);update();});
  $('detailAdd').addEventListener('click',()=>{
    if(product.available<=0||state.buyerBusy)return;
    try{const intent=protectedIntent('add',{productId:product.id,groupId:$('detailGroup').value,quantity:Number($('detailQuantity').value)});dialog.close();requireBuyer(intent);}catch{toast(phrase('invalidQuantity'));}
  });
  update();if(!dialog.open)dialog.showModal();
}
function requireBuyer(intent){
  if(!state.user){goAuth(intent);return;}
  runIntent(intent).catch(e=>toast(e.message||phrase('saveFailed')));
}
async function persistBuyer(cart,saved){
  if(!state.user)throw new Error(phrase('noAccount'));
  if(state.buyerBusy)throw new Error(phrase('processing'));
  const session=state.session;
  const active=document.activeElement;
  const focusKey=['adjust','remove','save'].find(key=>active?.dataset[key]);
  const focusValue=focusKey?active.dataset[focusKey]:null;
  state.buyerBusy=true;renderDrawer();renderCatalog();
  try{
    const response=await call('saveWholesaleBuyerState',{cart,saved});
    if(session!==state.session)return;
    state.cart=Array.isArray(response.cart)?response.cart:cart;
    state.saved=Array.isArray(response.saved)?response.saved:saved;
  }finally{
    state.buyerBusy=false;renderDrawer();renderCatalog();
    if(focusKey&&document.activeElement===document.body){
      const target=[...document.querySelectorAll('[data-'+focusKey+']')].find(node=>node.dataset[focusKey]===focusValue&&!node.disabled);
      (target||(!$('buyerDrawer').hidden?$('closeDrawer'):null))?.focus({preventScroll:true});
    }
  }
}
async function runIntent(intent) {
  if(!state.user)return goAuth(intent);
  if(intent.action==='add'){
    await persistBuyer(mergeCart(state.cart,{productId:intent.productId,groupId:intent.groupId,quantity:intent.quantity}),state.saved);
    toast(phrase('added'));
  } else if(intent.action==='save'){
    const exists=state.saved.includes(intent.productId);
    await persistBuyer(state.cart,exists?state.saved.filter(id=>id!==intent.productId):[...state.saved,intent.productId]);
    toast(phrase(exists?'saveRemoved':'saved'));
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
  if(!lines.length)return '<div class="empty-state">'+icon(mode==='cart'?'shopping-bag':'heart')+'<strong>'+esc(phrase(mode==='cart'?'cartEmpty':'savedEmpty'))+'</strong><p>'+esc(phrase('deskEmpty'))+'</p><button class="secondary-button" type="button" data-browse>'+esc(phrase('browse'))+'</button></div>';
  return lines.map((line,index)=>{
    const id=mode==='cart'?line.productId:line,product=getProduct(id),group=mode==='cart'?product?.groups.find(x=>x.id===line.groupId):null;
    const label=product?localized(product):id;
    const price=mode==='cart'?(group?money(group.priceMinor*line.quantity,product.currency):phrase('partialPrice')):'';
    const busy=state.buyerBusy||state.submitting?'disabled':'';
    return '<div class="drawer-item"><div class="drawer-thumbnail" aria-hidden="true">'+(product?.image?'<img src="'+esc(product.image)+'" alt="">':icon('package'))+'</div><div class="drawer-item-info"><strong>'+esc(label)+'</strong><small>'+(mode==='cart'?esc(String(line.quantity)+' × '+(group?localized(group):line.groupId)):'')+'</small><small class="line-price">'+esc(price)+'</small></div><div class="drawer-actions">'+
      (mode==='cart'?'<button type="button" '+busy+' data-adjust="'+index+':-1" aria-label="'+esc(phrase('decrease')+' · '+label)+'">'+icon('minus')+'</button><button type="button" '+busy+' data-adjust="'+index+':1" aria-label="'+esc(phrase('increase')+' · '+label)+'">'+icon('plus')+'</button>':'<button type="button" data-view="'+esc(id)+'" aria-label="'+esc(phrase('details')+' · '+label)+'">'+icon('arrow-right','directional')+'</button>')+
      '<button type="button" class="remove-line" '+busy+' data-remove="'+mode+':'+index+'">'+esc(phrase('remove'))+'</button></div></div>';
  }).join('');
}
function renderDrawer(){
  if($('buyerDrawer').hidden)return;
  const view=state.drawer;
  $('drawerHeading').textContent=phrase(view==='cart'?'cartHeading':view==='saved'?'savedHeading':'ordersHeading');
  document.querySelectorAll('[data-drawer]').forEach(b=>b.setAttribute('aria-current',String(b.dataset.drawer===view)));
  $('buyerSignOut').disabled=state.buyerBusy||state.submitting;
  const box=$('drawerContent'), selectedBranch=$('branchSelect')?.value;
  const focus=document.activeElement;
  const key=focus?.dataset.adjust?'adjust':focus?.dataset.remove?'remove':null;
  const value=key?focus.dataset[key]:null;
  box.setAttribute('aria-busy',String(state.ordersLoading&&view==='orders'||state.buyerBusy));
  if(view==='orders'&&(state.ordersLoading||state.ordersError)){
    box.innerHTML='<div class="empty-state">'+icon(state.ordersLoading?'receipt':'warning-circle')+'<strong>'+esc(phrase(state.ordersLoading?'processing':'saveFailed'))+'</strong></div>';
    if(state.ordersError){const retry=document.createElement('button');retry.type='button';retry.className='secondary-button';retry.textContent=phrase('retry');retry.addEventListener('click',()=>openDrawer('orders'));box.firstChild.append(retry);}return;
  }
  if(view==='cart'){
    const summary=cartSummary(state.cart,state.products);
    const branchOptions=state.branches.map(b=>'<option value="'+esc(b.id)+'">'+esc(localized(b))+'</option>').join('');
    box.innerHTML=formatDrawerRows(state.cart,'cart')+(state.cart.length?'<div class="checkout-area"><div class="drawer-total"><span>'+esc(phrase('total'))+'</span><strong>'+esc(summaryText(summary))+'</strong></div><label>'+esc(phrase('branch'))+'<select id="branchSelect" '+(state.submitting?'disabled':'')+'><option value="">'+esc(phrase('noBranch'))+'</option>'+branchOptions+'</select></label>'+(state.branches.length?'':'<p class="notice">'+esc(phrase('branchMissing'))+'</p>')+'<button type="button" class="primary-button" id="checkoutBtn" '+(!state.branches.length||state.submitting||state.buyerBusy?'disabled':'')+'>'+esc(phrase(state.submitting?'processing':'requestOrder'))+'</button><p class="notice">'+esc(phrase('draftNote'))+'</p></div>':'');
    if(selectedBranch&&$('branchSelect'))$('branchSelect').value=selectedBranch;
    $('checkoutBtn')?.addEventListener('click',submitOrder);
  }else if(view==='saved')box.innerHTML=formatDrawerRows(state.saved,'saved');
  else box.innerHTML=state.orders.length?state.orders.map(o=>'<div class="drawer-item"><div class="drawer-thumbnail" aria-hidden="true">'+icon('receipt')+'</div><div class="drawer-item-info"><strong>#'+esc(o.orderNumber||o.id)+'</strong><small><span class="status-tag" data-status="'+esc(o.status)+'">'+esc(phrase(o.status||'pending_review'))+'</span></small><small class="line-price">'+esc(money(o.totalMinor,o.currency))+'</small></div>'+(o.status==='pending_review'?'<button type="button" class="order-cancel" data-cancel="'+esc(o.id)+'">'+esc(phrase('cancelRequest'))+'</button>':'')+'</div>').join(''):'<div class="empty-state">'+icon('receipt')+'<strong>'+esc(phrase('ordersEmpty'))+'</strong><p>'+esc(phrase('deskEmpty'))+'</p><button class="secondary-button" type="button" data-browse>'+esc(phrase('browse'))+'</button></div>';
  if(key){const next=[...box.querySelectorAll('[data-'+key+']')].find(n=>n.dataset[key]===value);if(next&&!next.disabled)next.focus({preventScroll:true});}
}
let drawerReturnFocus=null;
function setWorkspaceInert(value){
  document.querySelectorAll('.skip-link,.topbar,.site-header,main,.footer,#orderDock').forEach(node=>node.inert=value);
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
  if(state.submitting||state.buyerBusy)return;
  const branchId=$('branchSelect')?.value;
  if(!branchId||!state.branches.some(b=>b.id===branchId)){toast(phrase('noBranch'));return;}
  if(!state.cart.length)return;
  state.submitting=true;renderDrawer();
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
$('searchInput').addEventListener('input',event=>{state.query=event.target.value.trim();renderCatalog();});
$('sortSelect').addEventListener('change',event=>{state.sort=event.target.value;renderCatalog();});
$('languageBtn').addEventListener('click',()=>{state.lang=state.lang==='ar'?'en':'ar';applyLanguage();});
$('clearSearch').addEventListener('click',()=>{state.query='';$('searchInput').value='';renderCatalog();$('searchInput').focus();});
for(const mode of ['grid','list'])$(mode+'View').addEventListener('click',()=>{state.view=mode;writePreference('view',mode);renderCatalog();});
$('deskContent').addEventListener('click',e=>{const b=e.target.closest('[data-desk]');if(b)requireBuyer(protectedIntent(b.dataset.desk));});
$('orderDock').addEventListener('click',()=>requireBuyer(protectedIntent('cart')));
document.querySelector('.drawer-tabs').addEventListener('click',e=>{const b=e.target.closest('[data-drawer]');if(b)openDrawer(b.dataset.drawer);});
$('loadMoreBtn').addEventListener('click',()=>loadCatalog());
$('productGrid').addEventListener('click',event=>{
  const save=event.target.closest('[data-save]');if(save){requireBuyer(protectedIntent('save',{productId:save.dataset.save}));return;}
  const open=event.target.closest('[data-open]');if(open)productDetails(open.dataset.open);
});
$('cartBtn').addEventListener('click',()=>requireBuyer(protectedIntent('cart')));
$('savedBtn').addEventListener('click',()=>{if(state.user)openDrawer('saved');else goAuth(protectedIntent('saved'));});
$('ordersNav').addEventListener('click',()=>requireBuyer(protectedIntent('orders')));
$('closeProduct').addEventListener('click',()=>$('productDialog').close());
$('closeDrawer').addEventListener('click',closeDrawer);
$('drawerScrim').addEventListener('click',closeDrawer);
$('closeAuth').addEventListener('click',()=>{state.pending=null;$('authDialog').close();});
$('accountBtn').addEventListener('click',()=>requireBuyer(protectedIntent('cart')));
$('buyerSignOut').addEventListener('click',async()=>{
  if(!state.backend||state.buyerBusy||state.submitting)return;
  try{await state.backend.signOut(state.backend.auth);state.pending=null;closeDrawer();renderDesk();}catch{toast(phrase('sessionFailed'));}
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
  if(event.target.closest('[data-browse]')){closeDrawer();$('catalog').scrollIntoView({behavior:'auto'});$('searchInput').focus({preventScroll:true});return;}
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
  if(state.buyerBusy||state.submitting)return;
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
applyLanguage();
loadCatalog(true);

// Broken upstream images use the same intentional empty state, without inline handlers.
document.addEventListener('error',event=>{const img=event.target;if(img instanceof HTMLImageElement && img.closest('.product-art,.detail-image,.drawer-thumbnail'))img.replaceWith(Object.assign(document.createElement('span'),{className:'placeholder-art',innerHTML:icon('package')}));},true);
