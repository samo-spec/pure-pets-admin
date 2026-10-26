
import { protectedIntent, mergeCart, normalizeCatalogItem } from './state.js';

const $ = (id) => document.getElementById(id);
const t = {
  ar: {
    top:'بوابة الأعمال من Pure Pets',wholesale:'تجربة مخصصة لطلبات الجملة',navCatalog:'المنتجات',navOrders:'طلباتي',
    cart:'السلة',login:'دخول / تسجيل',logout:'تسجيل الخروج',eyebrow:'PURE PETS / BUSINESS',heroOne:'الجملة،',heroTwo:'بمفهوم أذكى.',
    heroDesc:'منتجات مختارة بعناية، وحدات بيع واضحة، وتجربة طلب تناسب طموح تجارتك.',explore:'اكتشف المنتجات',
    guestHint:'تصفح بحرية. سجّل دخولك فقط عند اتخاذ إجراء.',collection:'THE COLLECTION / المجموعة',catalogHeading:'اكتشف مجموعتنا',
    catalogHint:'منتجات الجملة المتاحة حسب إعدادات المتجر الفعلية.',products:'منتج',search:'ابحث عن المنتجات...',
    sortFeatured:'الترتيب الافتراضي',sortLow:'الأقل سعراً',sortHigh:'الأعلى سعراً',loadMore:'عرض المزيد',
    promiseOne:'وحدات بيع واضحة',promiseTwo:'أسعار جملة موثقة',promiseThree:'طلبات مرتبطة بحسابك',footerCopy:'كل ما يحتاجه مشروعك، من مكان واحد.',
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
    units:'قطعة',verified:'سعر الجملة',noBranch:'اختر الفرع',cancelRequest:'إلغاء الطلب',cancelConfirm:'هل تريد إلغاء طلب الجملة المعلق؟',cancelSuccess:'تم إلغاء الطلب',increase:'زيادة الكمية',decrease:'تقليل الكمية'
  },
  en: {
    top:'The Pure Pets business gateway',wholesale:'A dedicated wholesale experience',navCatalog:'Products',navOrders:'My orders',
    cart:'Cart',login:'Sign in / Join',logout:'Sign out',eyebrow:'PURE PETS / BUSINESS',heroOne:'Wholesale,',heroTwo:'reimagined.',
    heroDesc:'Carefully chosen products, clear pack pricing, and a buying experience built around your business.',explore:'Explore the collection',
    guestHint:'Browse freely. Sign in only when you want to take action.',collection:'THE COLLECTION / WHOLESALE',catalogHeading:'Explore the collection',
    catalogHint:'Wholesale products published by the store.',products:'products',search:'Search products...',
    sortFeatured:'Featured first',sortLow:'Price: low to high',sortHigh:'Price: high to low',loadMore:'Load more',
    promiseOne:'Clear wholesale units',promiseTwo:'Verified pack pricing',promiseThree:'Orders tied to your account',footerCopy:'Everything your business needs, in one place.',
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
    units:'units',verified:'Wholesale price',noBranch:'Select branch',cancelRequest:'Cancel request',cancelConfirm:'Cancel this pending wholesale request?',cancelSuccess:'Request cancelled',increase:'Increase quantity',decrease:'Decrease quantity'
  }
};
const state = {
  lang: 'ar', products: [], cursor:null, categories:[], category:'all', query:'', sort:'featured',
  branches:[], cart:[], saved:[], user:null, backend:null, pending:null, activeProduct:null,
  authMode:'login', drawer:'cart', loadError:false, authReady:false, loading:false,
  submitting:false, orderCommandId:null, orders:[], notifyTimer:null
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
    if(phrase(key)!==key)node.textContent=phrase(key);
  });
  document.querySelectorAll('[data-placeholder]').forEach(node=>node.placeholder=phrase(node.dataset.placeholder));
  $('languageBtn').textContent=state.lang==='ar'?'EN':'عربي';
  $('accountBtn').textContent=state.user ? phrase('welcome') : phrase('login');
  renderCatalog(); renderDrawer();
}
function goAuth(intent) {
  if (state.user) return runIntent(intent);
  state.pending=intent;
  state.authMode='login';
  updateAuthTabs();
  $('authError').hidden=true;
  $('authDialog').showModal();
  $('emailInput').focus();
}
function updateAuthTabs() {
  $('loginTab').classList.toggle('active',state.authMode==='login');
  $('registerTab').classList.toggle('active',state.authMode==='register');
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
    state.user=user||null; state.authReady=true; state.cart=[];state.saved=[];state.orders=[];state.orderCommandId=null;
    $('accountBtn').textContent=user?phrase('welcome'):phrase('login');
    if(user) {
      try {
        const record=await call('getWholesaleBuyerState');
        state.cart=Array.isArray(record.cart)?record.cart:[];
        state.saved=Array.isArray(record.saved)?record.saved:[];
      } catch (error) { toast(phrase('saveFailed')); }
    }
    $('cartCount').textContent=String(state.cart.reduce((sum,line)=>sum+(Number(line.quantity)||0),0));
    renderDrawer();
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
    && (localized(p)+' '+p.id+' '+p.category).toLocaleLowerCase().includes(state.query.toLocaleLowerCase()));
  if(state.sort!=='featured') products=[...products].sort((a,b)=>((a.groups[0]?.priceMinor||0)-(b.groups[0]?.priceMinor||0)) *(state.sort==='priceDesc'?-1:1));
  return products;
}
function renderCatalog() {
  const tabs=$('categoryTabs');tabs.replaceChildren();
  const categories=['all',...new Set(state.products.map(p=>p.category))];
  if(!categories.includes(state.category))state.category='all';
  categories.forEach(category=>{
    const b=document.createElement('button');b.type='button';b.className='category-pill'+(category===state.category?' active':'');
    b.textContent=categoryTitle(category);b.setAttribute('aria-pressed',String(category===state.category));
    b.addEventListener('click',()=>{state.category=category;renderCatalog();});
    tabs.append(b);
  });
  const list=visibleProducts();
  $('productCount').textContent=String(list.length);
  const grid=$('productGrid');grid.replaceChildren();
  $('loadMoreBtn').hidden=!state.cursor||state.loading;
  if(state.loading && !state.products.length){
    for(let i=0;i<8;i++){const node=document.createElement('div');node.className='loading-card';grid.append(node);}
    return;
  }
  if(!list.length){
    const el=document.createElement('div');el.className='empty-state';
    const title=document.createElement('strong');title.textContent=state.loadError?phrase('unavailableTitle'):phrase('emptyTitle');
    const sub=document.createElement('p');sub.textContent=state.loadError?phrase('unavailableText'):(state.products.length?phrase('emptyText'):phrase('noProducts'));
    el.append(title,sub);
    if(state.loadError){const b=document.createElement('button');b.type='button';b.className='secondary-button';b.textContent=phrase('retry');b.addEventListener('click',()=>loadCatalog(true));el.append(b);}
    grid.append(el);return;
  }
  for(const item of list){
    const group=item.groups.find(g=>g.defaultForWholesale)||item.groups[0];
    const image=item.image?'<img src="'+esc(item.image)+'" loading="lazy" alt="'+esc(localized(item))+'">':'<span class="placeholder-art">PP</span>';
    const card=document.createElement('article');card.className='product-card';
    card.innerHTML='<button class="product-art" type="button" data-open="'+esc(item.id)+'" aria-label="'+esc(localized(item))+'">'+image+
      '<span class="pack-chip">'+esc(String(group.unitsPerGroup))+' '+esc(phrase('units'))+'</span></button>'+
      '<button type="button" class="save-float" data-save="'+esc(item.id)+'" aria-label="'+esc(phrase('save'))+'">♡</button>'+
      '<div class="card-body"><div class="card-type">'+esc(categoryTitle(item.category))+'</div><h3>'+esc(localized(item))+'</h3>'+
      '<p class="card-pack">'+esc(localized(group))+' · '+esc(String(group.unitsPerGroup))+' '+esc(phrase('units'))+'</p>'+
      '<div class="card-bottom"><div><span class="price-label">'+esc(phrase('from'))+'</span><div class="price-value">'+esc(money(group.priceMinor,item.currency))+'</div></div>'+
      '<button class="add-mini" type="button" data-open="'+esc(item.id)+'" aria-label="'+esc(phrase('details'))+'">+</button></div></div>';
    grid.append(card);
  }
}
function getProduct(id){return state.products.find(p=>p.id===id);}
function productDetails(id){
  const product=getProduct(id);if(!product)return;
  state.activeProduct=id;
  const image=product.image?'<img src="'+esc(product.image)+'" alt="'+esc(localized(product))+'">':'<span class="placeholder-art">PP</span>';
  const dialog=$('productDialog');
  $('productDetail').innerHTML='<div class="detail-layout"><div class="detail-image">'+image+'</div>'+
    '<div class="detail-info"><div class="section-kicker">'+esc(phrase('verified'))+'</div><h2>'+esc(localized(product))+'</h2>'+
    '<p>'+esc(categoryTitle(product.category))+'</p><label>'+esc(phrase('selectPack'))+'<select id="detailGroup">'+
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
  dialog.showModal();
}
function requireBuyer(intent){
  if(!state.user){goAuth(intent);return;}
  runIntent(intent).catch(e=>toast(e.message||phrase('saveFailed')));
}
async function persistBuyer(cart,saved){
  if(!state.user)throw new Error(phrase('noAccount'));
  const response=await call('saveWholesaleBuyerState',{cart,saved});
  state.cart=Array.isArray(response.cart)?response.cart:cart;
  state.saved=Array.isArray(response.saved)?response.saved:saved;
  $('cartCount').textContent=String(state.cart.reduce((sum,x)=>sum+x.quantity,0));
  renderDrawer();
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
  if(view==='cart'){
    const total=state.cart.reduce((n,line)=>n+(cartLinePrice(line)||0),0);
    const branchOptions=state.branches.map(b=>'<option value="'+esc(b.id)+'">'+esc(localized(b))+'</option>').join('');
    box.innerHTML=formatDrawerRows(state.cart,'cart')+
      (state.cart.length?'<div class="drawer-total"><span>'+esc(phrase('total'))+'</span><strong>'+esc(money(total,state.products[0]?.currency||'QAR'))+'</strong></div>'+
      '<label>'+esc(phrase('branch'))+'<select id="branchSelect">'+
      '<option value="">'+esc(phrase('noBranch'))+'</option>'+branchOptions+'</select></label>'+
      (state.branches.length?'':'<p class="notice">'+esc(phrase('branchMissing'))+'</p>')+
      '<button type="button" class="primary-button" id="checkoutBtn" '+(state.branches.length?'':'disabled')+'>'+esc(phrase('requestOrder'))+'</button>'+
      '<p class="notice">'+esc(phrase('draftNote'))+'</p>':'');
    $('checkoutBtn')?.addEventListener('click',()=>submitOrder());
  } else if(view==='saved') box.innerHTML=formatDrawerRows(state.saved,'saved');
  else box.innerHTML=state.orders.length?state.orders.map(o=>'<div class="drawer-item"><div><strong>#'+esc(o.orderNumber||o.id)+'</strong><small>'+esc(o.status||'pending_review')+'</small><small>'+esc(money(o.totalMinor,o.currency))+'</small></div>'+ (o.status==='pending_review'?'<button type="button" data-cancel="'+esc(o.id)+'" title="'+esc(phrase('cancelRequest'))+'">'+esc(phrase('cancelRequest'))+'</button>':'')+'</div>').join(''):'<div class="empty-state"><strong>'+esc(phrase('ordersEmpty'))+'</strong></div>';
}
async function openDrawer(view){
  if(!state.user)return goAuth(protectedIntent(view==='orders'?'orders':view==='saved'?'saved':'cart'));
  state.drawer=view; $('buyerDrawer').hidden=false;$('drawerScrim').hidden=false;
  if(view==='orders'){
    try{const data=await call('listWholesaleOrderRequests',{limit:30});state.orders=Array.isArray(data.items)?data.items:[];}
    catch{toast(phrase('saveFailed'));}
  }
  renderDrawer();$('closeDrawer').focus();
}
function closeDrawer(){$('buyerDrawer').hidden=true;$('drawerScrim').hidden=true;}
async function submitOrder(){
  if(state.submitting)return;
  const branchId=$('branchSelect')?.value;
  if(!branchId||!state.branches.some(b=>b.id===branchId)){toast(phrase('noBranch'));return;}
  if(!state.cart.length)return;
  state.submitting=true;
  const button=$('checkoutBtn');if(button){button.disabled=true;button.textContent=phrase('processing');}
  if(!state.orderCommandId)state.orderCommandId=crypto.randomUUID();
  try{
    const result=await call('createWholesaleOrderRequest',{commandId:state.orderCommandId,branchId,items:state.cart});
    if(!result?.ok || !result?.requestId)throw new Error('Order not acknowledged');
    state.orderCommandId=null;
    await persistBuyer([],state.saved);
    toast(phrase('requestSent'));closeDrawer();await openDrawer('orders');
  }catch(error){console.warn('Wholesale order request rejected',error?.code||error?.message);toast(phrase('requestFailed'));}
  finally{state.submitting=false;renderDrawer();}
}
$('searchInput').addEventListener('input',event=>{state.query=event.target.value.trim();renderCatalog();});
$('sortSelect').addEventListener('change',event=>{state.sort=event.target.value;renderCatalog();});
$('languageBtn').addEventListener('click',()=>{state.lang=state.lang==='ar'?'en':'ar';applyLanguage();});
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
$('accountBtn').addEventListener('click',()=>{
  if(!state.user)return goAuth(protectedIntent('cart'));
  if(confirm(state.lang==='ar'?'هل تريد تسجيل الخروج؟':'Sign out of your account?')){
    closeDrawer();state.cart=[];state.saved=[];state.pending=null;
    state.backend?.signOut(state.backend.auth).catch(()=>toast(phrase('sessionFailed')));
  }
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
applyLanguage();
(async()=>{try{await connectBackend();await loadCatalog(true);}catch(error){console.warn('Storefront startup:',error?.message);state.loadError=true;state.loading=false;renderCatalog();}})();
