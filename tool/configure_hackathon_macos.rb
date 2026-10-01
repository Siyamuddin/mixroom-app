#!/usr/bin/env ruby
# Rebuild only the independent Hackathon configurations. No compilation,
# credential loading, project copying, or external service access occurs here.
require 'base64'
require 'rexml/document'
require 'xcodeproj'

repo_root = File.expand_path('..', __dir__)
macos_root = File.join(repo_root, 'macos')
project_path = File.join(macos_root, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
define = Base64.strict_encode64('MIXROOM_HACKATHON=true')

def file_reference(project, relative_path)
  project.files.find { |file| file.real_path.to_s == File.join(project.path.dirname, relative_path) } ||
    project.main_group.new_file(relative_path)
end

%w[Debug Profile Release].each do |mode|
  name = "#{mode}-Hackathon"
  project_base = project.build_configurations.find { |config| config.name == mode }
  raise "Missing #{mode} configuration" unless project_base
  config = project.build_configurations.find { |item| item.name == name } ||
    project.add_build_configuration(name, mode == 'Debug' ? :debug : :release)
  config.build_settings = Marshal.load(Marshal.dump(project_base.build_settings))
  config.base_configuration_reference = file_reference(project, "Runner/Configs/#{name}.xcconfig")

  project.targets.each do |target|
    base = target.build_configurations.find { |item| item.name == mode }
    next unless base
    target_config = target.build_configurations.find { |item| item.name == name } ||
      target.add_build_configuration(name, mode == 'Debug' ? :debug : :release)
    target_config.build_settings = Marshal.load(Marshal.dump(base.build_settings))
    target_config.base_configuration_reference = base.base_configuration_reference
    settings = target_config.build_settings
    # The generated Flutter settings remain inherited; force the isolation flag
    # for both Runner and Flutter Assemble without dropping public relay defines.
    settings['DART_DEFINES'] = "$(inherited),#{define}"
    settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) MIXROOM_HACKATHON'
    settings['DEVELOPMENT_TEAM'] = ''
    settings['CODE_SIGN_STYLE'] = 'Manual'
    settings['CODE_SIGN_IDENTITY'] = '-'
    settings['PROVISIONING_PROFILE_SPECIFIER'] = ''
    settings.delete('OTHER_CODE_SIGN_FLAGS')
    if target.name == 'Runner'
      target_config.base_configuration_reference = file_reference(project, 'Runner/Configs/AppInfo-Hackathon.xcconfig')
      settings['INFOPLIST_FILE'] = 'Runner/Hackathon-Info.plist'
      settings['CODE_SIGN_ENTITLEMENTS'] = mode == 'Release' ? 'Runner/Hackathon-Release.entitlements' : 'Runner/Hackathon-DebugProfile.entitlements'
      settings['ENABLE_HARDENED_RUNTIME'] = 'NO'
    elsif target.name == 'RunnerTests'
      target_config.base_configuration_reference = file_reference(project, "Pods/Target Support Files/Pods-RunnerTests/Pods-RunnerTests.#{name.downcase}.xcconfig")
      settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.github.siyamuddin.mixroom.hackathon.RunnerTests'
      settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/MixRoom.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MixRoom'
    end
  end
end

%w[Hackathon-Info.plist Hackathon-DebugProfile.entitlements Hackathon-Release.entitlements].each do |file|
  file_reference(project, "Runner/#{file}")
end
project.save

# Derive a separate plist while retaining microphone permission and attribution.
info_path = File.join(macos_root, 'Runner/Info.plist')
info = Xcodeproj::Plist.read_from_path(info_path)
%w[CFBundleURLTypes GIDClientID GIDServerClientID SUFeedURL SUPublicEDKey SUScheduledCheckInterval].each { |key| info.delete(key) }
info['CFBundleDisplayName'] = 'MixRoom'
info['CFBundleName'] = '$(PRODUCT_NAME)'
info['MixRoomHackathonBuild'] = true
info['SUEnableAutomaticChecks'] = false
info['SUAutomaticallyUpdate'] = false
# The original app owns the project format; this independent app may open it.
info.fetch('CFBundleDocumentTypes', []).each { |type| type['LSHandlerRank'] = 'Alternate' }
if info['UTExportedTypeDeclarations']
  info['UTImportedTypeDeclarations'] = info.delete('UTExportedTypeDeclarations')
end
Xcodeproj::Plist.write_to_path(info, File.join(macos_root, 'Runner/Hackathon-Info.plist'))

%w[DebugProfile Release].each do |mode|
  entitlements = Xcodeproj::Plist.read_from_path(File.join(macos_root, "Runner/#{mode}.entitlements"))
  %w[com.apple.developer.applesignin keychain-access-groups application-identifier com.apple.developer.team-identifier].each { |key| entitlements.delete(key) }
  Xcodeproj::Plist.write_to_path(entitlements, File.join(macos_root, "Runner/Hackathon-#{mode}.entitlements"))
end

scheme_path = File.join(project_path, 'xcshareddata/xcschemes/Runner.xcscheme')
scheme = REXML::Document.new(File.read(scheme_path))
REXML::XPath.each(scheme, '//*[@buildConfiguration]') do |element|
  element.attributes['buildConfiguration'] = "#{element.attributes['buildConfiguration']}-Hackathon"
end
REXML::XPath.each(scheme, '//BuildableReference') do |element|
  element.attributes['BuildableName'] = 'MixRoom.app' if element.attributes['BlueprintName'] == 'Runner'
end
File.open(File.join(File.dirname(scheme_path), 'Hackathon.xcscheme'), 'w') do |file|
  formatter = REXML::Formatters::Pretty.new(3)
  formatter.compact = true
  formatter.write(scheme, file)
  file.write("\n")
end
puts 'Updated independent Hackathon macOS configurations; no build was started.'
