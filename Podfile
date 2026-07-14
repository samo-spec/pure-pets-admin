platform :ios, '13.0'
#A8FA0353-3356-456B-9AF3-46DD11AB9108
target 'PurePetsAdmin' do
  
  use_frameworks! :linkage => :static
  #inhibit_all_warnings!
  pod 'YYKit', :inhibit_warnings => true
 
  
  # ===== UI & Media =====
  pod 'SDWebImage'
  pod 'lottie-ios', '~> 2.5.3'
  pod 'XLForm'
  pod 'IQKeyboardManager'
  
  
  pod 'SSZipArchive'
 
  pod 'ShowTime'
     
   pod 'TOCropViewController'
  
end

post_install do |installer|
  admin_header_paths = [
    '${PODS_ROOT}/XLForm/XLForm/XL',
    '${PODS_ROOT}/XLForm/XLForm/XL/**',
    '${PODS_ROOT}/HXPhotoPickerObjC/HXPhotoPicker',
    '${PODS_ROOT}/HXPhotoPickerObjC/HXPhotoPicker/**',
    '${PODS_ROOT}/TOCropViewController/Objective-C/TOCropViewController',
    '${PODS_ROOT}/TOCropViewController/Objective-C/TOCropViewController/**',
     '${PODS_ROOT}/YYKit/YYKit',
    '${PODS_ROOT}/YYKit/YYKit/**',
    '${PODS_ROOT}/SSZipArchive/SSZipArchive',
    '${PODS_ROOT}/SSZipArchive/SSZipArchive/**',
    '${PODS_ROOT}/SDWebImage/SDWebImage/Core',
    '${PODS_ROOT}/SDWebImage/SDWebImage/Core/**',
    '${PODS_ROOT}/SDWebImage/WebImage',
    '${PODS_ROOT}/lottie-ios/lottie-ios/Classes/PublicHeaders',
    '${PODS_ROOT}/lottie-ios/lottie-ios/Classes/PublicHeaders/**',
    '${PODS_ROOT}/FirebaseCore/FirebaseCore/Sources/Public/FirebaseCore',
    '${PODS_ROOT}/FirebaseMessaging/FirebaseMessaging/Sources/Public/FirebaseMessaging',
    '${PODS_ROOT}/FirebaseAuth/FirebaseAuth/Sources/Public/FirebaseAuth',
    '${PODS_ROOT}/FirebaseFirestore/FirebaseFirestoreInternal/FirebaseFirestore',
    '${PODS_ROOT}/FirebaseFirestore/FirebaseFirestoreInternal/FirebaseFirestore/**'
  ]

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete("EXCLUDED_ARCHS[sdk=iphonesimulator*]")
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
    # Suppress chained-comparison error in YYKit (unmaintained pod)
    if target.name == 'YYKit'
      target.build_configurations.each do |config|
        flags = config.build_settings['OTHER_CFLAGS'] || '$(inherited)'
        unless flags.include?('-Wno-parentheses')
          config.build_settings['OTHER_CFLAGS'] = "#{flags} -Wno-parentheses"
        end
      end
    end
    # Fix FirebaseFirestore-Swift.h not found (Xcode 16+)
    if target.name == 'FirebaseFirestore'
      target.build_configurations.each do |config|
        config.build_settings['SWIFT_INSTALL_OBJC_HEADER'] = 'NO'
      end
    end
  end

  installer.aggregate_targets.each do |aggregate_target|
    user_project = aggregate_target.user_project
    user_project.native_targets.each do |target|
      next unless ['PurePetsAdmin', 'PurePetsAdminTests', 'PurePetsAdminUITests'].include?(target.name)

      target.build_configurations.each do |config|
        existing = config.build_settings['HEADER_SEARCH_PATHS']
        existing = ['$(inherited)'] if existing.nil?
        existing = [existing] unless existing.is_a?(Array)

        config.build_settings['HEADER_SEARCH_PATHS'] = (existing + admin_header_paths).uniq
      end
    end
    user_project.save
  end
end
