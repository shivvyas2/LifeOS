# Adds the LifeOS Focus app target to LIfeOS.xcodeproj. Safe to re-run: it
# does nothing if the target already exists.
#   ruby scripts/add-focus-target.rb
require "xcodeproj"

PROJECT = File.expand_path("../LIfeOS.xcodeproj", __dir__)
NAME = "LifeOSFocus"
PRODUCTS = %w[AccountUI DesignSystem Integrations Persistence FocusSync FocusExperience Soundscape]

project = Xcodeproj::Project.open(PROJECT)
package = project.root_object.package_references.find { |r| r.respond_to?(:relative_path) && r.relative_path.to_s.include?("LifeOSKit") } \
  or abort("no local LifeOSKit package reference")

def link(project, target, package, product)
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = package
  dependency.product_name = product
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

# An existing target only gains the products it is missing.
if (existing = project.targets.find { |t| t.name == NAME })
  missing = PRODUCTS - existing.package_product_dependencies.map(&:product_name)
  if missing.empty?
    puts "#{NAME} already exists"
  else
    missing.each { |product| link(project, existing, package, product) }
    project.save
    puts "updated #{NAME}: #{missing.join(", ")}"
  end
  exit 0
end

target = project.new_target(:application, NAME, :ios, "26.0")

# Sources: one synchronized folder, like the LifeOS app, so new files need
# no project edits. Info.plist is excluded from its build phases.
group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
group.path = NAME
group.source_tree = "<group>"
exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
exceptions.target = target
exceptions.membership_exceptions = ["Info.plist"]
group.exceptions << exceptions
project.main_group.children << group
target.file_system_synchronized_groups << group

# Package products from the local LifeOSKit package.
PRODUCTS.each { |product| link(project, target, package, product) }

secrets = project.files.find { |f| f.path == "Config/Secrets.xcconfig" } or abort("no Secrets.xcconfig reference")
target.build_configurations.each do |config|
  config.base_configuration_reference = secrets
  s = config.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "com.shivvyas.lifeos.focus"
  s["PRODUCT_NAME"] = "$(TARGET_NAME)"
  s["DEVELOPMENT_TEAM"] = "Z42YU5W6WY"
  s["CODE_SIGN_STYLE"] = "Automatic"
  s["CODE_SIGN_ENTITLEMENTS"] = "#{NAME}/#{NAME}.entitlements"
  s["GENERATE_INFOPLIST_FILE"] = "YES"
  s["INFOPLIST_FILE"] = "#{NAME}/Info.plist"
  s["INFOPLIST_KEY_CFBundleDisplayName"] = "LifeOS Focus"
  s["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  s["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] = "YES"
  s["INFOPLIST_KEY_UISupportedInterfaceOrientations"] = "UIInterfaceOrientationPortrait"
  s["INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad"] =
    "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
  s["IPHONEOS_DEPLOYMENT_TARGET"] = "26.0"
  s["TARGETED_DEVICE_FAMILY"] = "1,2"
  s["SWIFT_VERSION"] = "6.0"
  s["MARKETING_VERSION"] = "1.0"
  s["CURRENT_PROJECT_VERSION"] = "1"
  s["ASSETCATALOG_COMPILER_APPICON_NAME"] = ""
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(PROJECT, NAME, true)
puts "added #{NAME}"
