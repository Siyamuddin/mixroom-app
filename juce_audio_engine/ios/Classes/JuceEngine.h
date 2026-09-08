#pragma once

#include "JuceHeader.h"
#include "SimpleGainProcessor.h"
#include "NativeEffects.h"
#include "JuceLogBridge.h"
#include "../../native/RealtimeWavCapture.h"
#include "../../native/MacIndependentMonitorBuffer.h"
#include "../../native/SampledPitchSemantics.h"
#include "../../native/TimelineMidiBoundary.h"

#include <array>
#include <atomic>
#include <algorithm>
#include <bitset>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cmath>
#include <deque>
#include <functional>
#include <limits>
#include <memory>
#include <mutex>
#include <regex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

extern "C" void juceLogToFlutter(const char *msg);
#if JUCE_MAC && !JUCE_IOS
extern "C" void mixroomPluginScanProgress(const char *json);
#endif
extern "C" void mixroomConfigureHostedPluginWindow(void *nativeHandle,
                                                    int scopeKind,
                                                    int row,
                                                    int effectIndex,
                                                    int clipId,
                                                    void *ownerHandle,
                                                    bool usesMixroomShell,
                                                    bool editorResizable);
extern "C" void mixroomPostHostedPluginAutomationSelection(
    int scopeKind,
    int row,
    int effectIndex,
    int clipId,
    const char *paramId,
    const char *paramName);
extern "C" void mixroomRequestHostedPluginEditorClose(void *ownerHandle);
extern "C" void mixroomRequestHostedPluginAutomationForOwner(void *ownerHandle);
extern "C" void mixroomSetHostedPluginWindowDetachedForOwner(void *ownerHandle,
                                                             bool detached);
extern "C" void *mixroomGetFlutterHostNativeView(void);
extern "C" bool mixroomGetNativeViewSize(void *nativeView,
                                          double *width,
                                          double *height);
extern "C" bool mixroomGetFlutterHostWindowContentSize(double *width,
                                                        double *height);
extern "C" void mixroomSetNativeViewFrameScale(void *nativeView,
                                                double x,
                                                double y,
                                                double logicalWidth,
                                                double logicalHeight,
                                                double scale);
extern "C" void mixroomConfigureEmbeddedPluginChrome(void *nativeView,
                                                      const char *title,
                                                      void *ownerHandle,
                                                      double scale);
extern "C" void mixroomReleaseEmbeddedPluginChrome(void *nativeView);
extern "C" void mixroomCloseHostedPluginNativeWindowsForOwner(void *ownerHandle);
extern "C" void mixroomAdoptHostedPluginAuxiliaryWindows(int scopeKind,
                                                          int row,
                                                          int effectIndex,
                                                          int clipId,
                                                          void *ownerHandle);

class MetronomeAudioCallback;
class IOSBluetoothDuplexProbeCallback;

class RoutedClipSource
{
public:
    virtual ~RoutedClipSource() = default;
    virtual void processRoutedClipsForRow(int rowId,
                                          const void *rowSchedule,
                                          juce::AudioBuffer<float> &buffer,
                                          juce::MidiBuffer &midi,
                                          juce::AudioBuffer<float> &scratchBuffer,
                                          juce::MidiBuffer &scratchMidi) = 0;
};

struct DecodedClipAudioAsset
{
    juce::AudioBuffer<float> audio;
    double sampleRate = 44100.0;
};

static constexpr int kMixroomRealtimeScratchMaxSamples = 32768;
static constexpr double kMixroomRoutedClipBucketSeconds = 4.0;
static constexpr double kMixroomRoutedMidiTailSeconds = 4.0;

enum class HostedPluginEditorScopeKind
{
    unknown = 0,
    trackEffect = 1,
    masterEffect = 2,
    midiClip = 3,
};

struct HostedPluginEditorMetadata
{
    HostedPluginEditorScopeKind scope = HostedPluginEditorScopeKind::unknown;
    int row = -1;
    int effectIndex = -1;
    int clipId = -1;
};

inline juce::String mixroomParameterIdForAutomation(
    juce::AudioProcessorParameter *parameter)
{
    if (parameter == nullptr)
        return {};
    if (auto *withId =
            dynamic_cast<juce::AudioProcessorParameterWithID *>(parameter))
        return withId->paramID;
    return parameter->getName(128).trim();
}

class HostedPluginAutomationContextMenu final
    : public juce::HostProvidedContextMenu
{
public:
    HostedPluginAutomationContextMenu(HostedPluginEditorMetadata metadataIn,
                                      juce::AudioProcessorParameter *parameterIn,
                                      juce::AudioProcessorEditor &editorIn)
        : metadata(metadataIn),
          parameter(parameterIn),
          editor(editorIn)
    {
    }

    juce::PopupMenu getEquivalentPopupMenu() const override
    {
        juce::PopupMenu menu;
        const auto parameterName = parameter != nullptr
                                       ? parameter->getName(128).trim()
                                       : juce::String();
        const auto label = parameterName.isNotEmpty()
                               ? "Automate " + parameterName
                               : "Choose Parameter to Automate…";
        menu.addItem(label,
                     true,
                     false,
                     [metadata = metadata,
                      parameterId = mixroomParameterIdForAutomation(parameter),
                      parameterName]()
                     {
                         mixroomPostHostedPluginAutomationSelection(
                             static_cast<int>(metadata.scope),
                             metadata.row,
                             metadata.effectIndex,
                             metadata.clipId,
                             parameterId.toRawUTF8(),
                             parameterName.toRawUTF8());
                     });
        return menu;
    }

    void showNativeMenu(juce::Point<int> pos) const override
    {
        auto menu = getEquivalentPopupMenu();
        const auto screenPoint = editor.localPointToGlobal(pos);
        menu.showMenuAsync(
            juce::PopupMenu::Options().withTargetScreenArea(
                juce::Rectangle<int>(screenPoint.x, screenPoint.y, 1, 1)));
    }

private:
    HostedPluginEditorMetadata metadata;
    juce::AudioProcessorParameter *parameter = nullptr;
    juce::AudioProcessorEditor &editor;
};

class HostedPluginEditorHostContext final
    : public juce::AudioProcessorEditorHostContext
{
public:
    HostedPluginEditorHostContext(HostedPluginEditorMetadata metadataIn,
                                  juce::AudioProcessorEditor &editorIn)
        : metadata(metadataIn), editor(editorIn)
    {
    }

    std::unique_ptr<juce::HostProvidedContextMenu>
    getContextMenuForParameter(
        const juce::AudioProcessorParameter *parameter) const override
    {
        return std::make_unique<HostedPluginAutomationContextMenu>(
            metadata,
            const_cast<juce::AudioProcessorParameter *>(parameter),
            editor);
    }

private:
    HostedPluginEditorMetadata metadata;
    juce::AudioProcessorEditor &editor;
};

class HostedPluginParameterTouchTracker final
    : public juce::AudioProcessorParameter::Listener
{
public:
    explicit HostedPluginParameterTouchTracker(juce::AudioProcessor *processorIn)
        : processor(processorIn)
    {
        if (processor == nullptr)
            return;
        const auto parameters = processor->getParameters();
        for (auto *parameter : parameters)
        {
            if (parameter == nullptr)
                continue;
            parameter->addListener(this);
            listenedParameters.push_back(parameter);
        }
    }

    ~HostedPluginParameterTouchTracker() override
    {
        for (auto *parameter : listenedParameters)
        {
            if (parameter != nullptr)
                parameter->removeListener(this);
        }
    }

    void parameterValueChanged(int parameterIndex, float) override
    {
        if (parameterIndex >= 0)
            lastChangedParameterIndex.store(parameterIndex,
                                            std::memory_order_relaxed);
    }

    void parameterGestureChanged(int parameterIndex, bool gestureIsStarting) override
    {
        if (gestureIsStarting)
        {
            noteParameterIndex(parameterIndex);
            lastGesturedParameterIndex.store(parameterIndex,
                                              std::memory_order_relaxed);
        }
    }

    void noteParameterIndex(int parameterIndex) noexcept
    {
        if (parameterIndex >= 0)
        {
            lastTouchedParameterIndex.store(parameterIndex,
                                            std::memory_order_relaxed);
            lastGesturedParameterIndex.store(parameterIndex,
                                              std::memory_order_relaxed);
        }
    }

    int getLastTouchedParameterIndex() const noexcept
    {
        const int gestured =
            lastGesturedParameterIndex.load(std::memory_order_relaxed);
        return gestured >= 0
                   ? gestured
                   : lastChangedParameterIndex.load(std::memory_order_relaxed);
    }

private:
    juce::AudioProcessor *processor = nullptr;
    std::vector<juce::AudioProcessorParameter *> listenedParameters;
    std::atomic<int> lastTouchedParameterIndex{-1};
    std::atomic<int> lastGesturedParameterIndex{-1};
    std::atomic<int> lastChangedParameterIndex{-1};
};

class HostedPluginEditorShell;

inline void mixroomResolveHostedPluginEditorMaxSize(int &maxEditorWidth,
                                                    int &maxEditorHeight)
{
    maxEditorWidth = 1400;
    maxEditorHeight = 920;
#if JUCE_MAC
    double hostWidth = 0.0;
    double hostHeight = 0.0;
    const bool hasHostWindow =
        mixroomGetFlutterHostWindowContentSize(&hostWidth, &hostHeight);
    if (hasHostWindow)
    {
        const int displayMaxWidth =
            juce::jmax(360, (int)std::round(hostWidth) - 48);
        const int displayMaxHeight =
            juce::jmax(220, (int)std::round(hostHeight) - 48);
        maxEditorWidth =
            juce::jmax(360,
                       juce::jmin(displayMaxWidth,
                                  1400));
        maxEditorHeight =
            juce::jmax(220,
                       juce::jmin(displayMaxHeight,
                                  920));
    }
    else if (auto *display =
                 juce::Desktop::getInstance().getDisplays().getPrimaryDisplay())
    {
        const int displayMaxWidth =
            juce::jmax(360, display->userArea.getWidth() - 48);
        const int displayMaxHeight =
            juce::jmax(220, display->userArea.getHeight() - 48);
        maxEditorWidth =
            juce::jmax(360,
                       juce::jmin(displayMaxWidth,
                                  1400));
        maxEditorHeight =
            juce::jmax(220,
                       juce::jmin(displayMaxHeight,
                                  920));
    }
#endif
}

class HostedPluginEditorWindow : public juce::DocumentWindow
{
public:
    using OnClose = std::function<void()>;

    HostedPluginEditorWindow(const juce::String &title,
                             juce::AudioProcessorEditor *editor,
                             juce::AudioProcessor *parameterProcessorIn,
                             HostedPluginEditorMetadata metadata,
                             bool showInitially,
                             OnClose onClose);

    bool matchesMetadata(const HostedPluginEditorMetadata &other) const noexcept
    {
        return metadata.scope == other.scope && metadata.row == other.row &&
               metadata.effectIndex == other.effectIndex &&
               metadata.clipId == other.clipId;
    }

    bool showAutomationContextMenuAtContentPoint(juce::Point<int> contentPoint);
    bool requestAutomationForLastTouchedParameter();
    bool supportsAutomationRequests() const noexcept
    {
        return automationScopeSupported();
    }

    void presentFromHost()
    {
        closeRequested = false;
#if JUCE_MAC
        const auto generation = ++presentationGeneration;
        fitMacNativePluginEditorWindow();
#endif
        setAlpha(1.0f);
        setVisible(true);
#if JUCE_MAC
        toFront(true);
        juce::Component::SafePointer<HostedPluginEditorWindow> safeThis(this);
        juce::Timer::callAfterDelay(16, [safeThis, generation]()
                                    {
            if (safeThis != nullptr &&
                safeThis->presentationGeneration == generation &&
                safeThis->isShowing())
            {
                safeThis->fitMacNativePluginEditorWindow();
                safeThis->toFront(true);
            } });
        juce::Timer::callAfterDelay(160, [safeThis]()
                                    {
            if (safeThis != nullptr)
            {
                mixroomAdoptHostedPluginAuxiliaryWindows(
                    static_cast<int>(safeThis->metadata.scope),
                    safeThis->metadata.row,
                    safeThis->metadata.effectIndex,
                    safeThis->metadata.clipId,
                    safeThis.getComponent());
            } });
#endif
    }

    void requestCloseFromHost()
    {
        closeButtonPressed();
    }

    void requestDestroyFromHost()
    {
        destroyOnClose = true;
        closeButtonPressed();
    }

    void setDetached(bool shouldDetach);

    bool isDetached() const noexcept
    {
        return detached;
    }

    ~HostedPluginEditorWindow() override;

    void closeButtonPressed() override
    {
        if (closeRequested)
            return;
        closeRequested = true;
#if JUCE_MAC
        ++presentationGeneration;
#endif
        if (destroyOnClose)
            releaseEmbeddedNativeChrome();
        setVisible(false);
        if (!destroyOnClose)
        {
            closeRequested = false;
            return;
        }
        auto onClose = onCloseFn;
#if JUCE_MAC
        juce::Timer::callAfterDelay(250, [onClose = std::move(onClose)]() mutable
                                    {
            if (onClose)
                onClose(); });
#else
        juce::MessageManager::callAsync([onClose = std::move(onClose)]() mutable
                                        {
            if (onClose)
                onClose(); });
#endif
    }

private:
    bool attachToFlutterHostView();
    void attachToDesktopWindowFallback();
    void configureDesktopPeerWindow();
    void fitMacNativePluginEditorWindow();
    void setEmbeddedNativeChromeActive(bool isActive);
    void releaseEmbeddedNativeChrome();
    bool postAutomationRequestForParameterIndex(int parameterIndex);
    bool automationScopeSupported() const noexcept;

    HostedPluginEditorMetadata metadata;
    juce::AudioProcessor *parameterProcessor = nullptr;
    HostedPluginParameterTouchTracker parameterTouchTracker;
    std::unique_ptr<HostedPluginEditorHostContext> hostContext;
    juce::String editorTitle;
    bool automationMenuOpen = false;
    bool detached = false;
    bool embeddedInFlutterHostView = false;
    float embeddedNativeViewScale = 1.0f;
    bool closeRequested = false;
    bool destroyOnClose = false;
#if JUCE_MAC
    uint32_t presentationGeneration = 0;
#endif
    OnClose onCloseFn;
};

class HostedPluginEditorShell final : public juce::Component
{
public:
    static constexpr int kHeaderHeight = 42;
    static constexpr int kResizeHandleSize = 16;

    static int extraChromeHeight() noexcept { return kHeaderHeight + 2; }

    HostedPluginEditorShell(juce::Component &ownerComponent,
                            juce::ComponentBoundsConstrainer *constrainer,
                            std::function<void()> onClose,
                            std::function<void()> onToggleDetach,
                            const juce::String &title,
                            juce::AudioProcessorEditor *editor,
                            bool editorResizable,
                            int naturalEditorWidth,
                            int naturalEditorHeight,
                            float editorScale)
        : owner(ownerComponent),
          onCloseFn(std::move(onClose)),
          onToggleDetachFn(std::move(onToggleDetach)),
          editorOwned(editor),
          titleLabel({}, title),
          naturalEditorWidth(naturalEditorWidth),
          naturalEditorHeight(naturalEditorHeight),
          editorScale(editorScale)
    {
        jassert(editorOwned != nullptr);
        addAndMakeVisible(titleLabel);
        titleLabel.setJustificationType(juce::Justification::centredLeft);
        titleLabel.setInterceptsMouseClicks(false, false);
        titleLabel.setColour(juce::Label::textColourId,
                             juce::Colours::white.withAlpha(0.9f));
        titleLabel.setFont(juce::Font(14.0f, juce::Font::bold));

        addAndMakeVisible(optionsButton);
        optionsButton.setButtonText("...");
        optionsButton.setColour(juce::TextButton::buttonColourId,
                                juce::Colour(0xff182231));
        optionsButton.setColour(juce::TextButton::buttonOnColourId,
                                juce::Colour(0xff243248));
        optionsButton.setColour(juce::TextButton::textColourOffId,
                                juce::Colours::white.withAlpha(0.72f));
        optionsButton.onClick = [this]()
        {
            juce::PopupMenu menu;
            if (auto *window =
                    dynamic_cast<HostedPluginEditorWindow *>(&owner))
            {
                if (window->supportsAutomationRequests())
                {
                    menu.addItem("Automate Last Touched Parameter",
                                 true,
                                 false,
                                 [window]()
                                 {
                                     window->requestAutomationForLastTouchedParameter();
                                 });
                    menu.addSeparator();
                }
            }
            menu.addItem(isDetached ? "Dock Plugin Window" : "Float Plugin Window",
                         true,
                         false,
                         [this]()
                         {
                             if (onToggleDetachFn)
                                 onToggleDetachFn();
                         });
            menu.showMenuAsync(juce::PopupMenu::Options().withTargetComponent(&optionsButton));
        };

        addAndMakeVisible(closeButton);
        closeButton.setButtonText("x");
        closeButton.setColour(juce::TextButton::buttonColourId,
                              juce::Colour(0xff1b2431));
        closeButton.setColour(juce::TextButton::buttonOnColourId,
                              juce::Colour(0xff334155));
        closeButton.setColour(juce::TextButton::textColourOffId,
                              juce::Colours::white.withAlpha(0.82f));
        closeButton.onClick = [this]()
        {
            if (onCloseFn)
                onCloseFn();
        };

        addAndMakeVisible(editorViewport);
        editorViewport.addAndMakeVisible(*editorOwned);
        editorOwned->addMouseListener(this, true);

        if (editorResizable)
        {
            resizeCorner = std::make_unique<juce::ResizableCornerComponent>(
                &owner,
                constrainer);
            addAndMakeVisible(*resizeCorner);
        }
    }

    ~HostedPluginEditorShell() override
    {
        if (editorOwned != nullptr)
            editorOwned->removeMouseListener(this);
    }

    juce::AudioProcessorEditor *getEditor() const noexcept
    {
        return editorOwned.get();
    }

    void setDetached(bool isDetached)
    {
        this->isDetached = isDetached;
    }

    void setEmbeddedNativeChromeActive(bool isActive)
    {
        titleLabel.setVisible(true);
        optionsButton.setVisible(!isActive);
        closeButton.setVisible(!isActive);
    }

    bool isPointInsideEditor(juce::Point<int> contentPoint) const noexcept
    {
        return editorOwned != nullptr && lastEditorArea.contains(contentPoint);
    }

    juce::Point<int> contentPointToEditor(juce::Point<int> contentPoint) const noexcept
    {
        if (editorOwned == nullptr)
            return contentPoint;
        const auto relative = contentPoint - lastEditorArea.getPosition();
        if (editorScale < 0.999f)
            return {
                (int)std::round((float)relative.x / editorScale),
                (int)std::round((float)relative.y / editorScale),
            };
        return relative;
    }

    void paint(juce::Graphics &g) override
    {
        auto bounds = getLocalBounds().toFloat();
        g.setColour(juce::Colour(0xff0d121a));
        g.fillRoundedRectangle(bounds, 10.0f);

        auto header = getLocalBounds().removeFromTop(kHeaderHeight).toFloat();
        juce::ColourGradient headerGradient(
            juce::Colour(0xff1a2432),
            0.0f,
            0.0f,
            juce::Colour(0xff101823),
            0.0f,
            (float)kHeaderHeight,
            false);
        g.setGradientFill(headerGradient);
        g.fillRoundedRectangle(header, 10.0f);
        g.fillRect(header.withTrimmedTop(10.0f));
        g.setColour(juce::Colour(0xff62d0ff).withAlpha(0.16f));
        g.fillRoundedRectangle(
            juce::Rectangle<float>(12.0f, 11.0f, 4.0f, 20.0f),
            3.0f);
        g.setColour(juce::Colours::white.withAlpha(0.08f));
        g.drawLine(12.0f,
                   (float)kHeaderHeight,
                   bounds.getWidth() - 12.0f,
                   (float)kHeaderHeight,
                   1.0f);
        g.setColour(juce::Colours::white.withAlpha(0.14f));
        g.drawRoundedRectangle(bounds.reduced(0.5f), 10.0f, 1.0f);
    }

    void resized() override
    {
        auto area = getLocalBounds();
        area.removeFromTop(kHeaderHeight);
        const int controlWidth = 34;
        const int controlHeight = 26;
        const int controlGap = 8;
        const int rightInset = 12;
        const int controlY = (kHeaderHeight - controlHeight) / 2;
        closeButton.setBounds(
            getWidth() - rightInset - controlWidth,
            controlY,
            controlWidth,
            controlHeight);
        optionsButton.setBounds(
            closeButton.getX() - controlGap - controlWidth,
            controlY,
            controlWidth,
            controlHeight);
        titleLabel.setBounds(
            25,
            0,
            juce::jmax(80, optionsButton.getX() - 33),
            kHeaderHeight);
        if (editorOwned != nullptr)
        {
            lastEditorArea = area.reduced(1, 1);
            editorOwned->setTransform({});
            editorViewport.setTransform({});
            editorViewport.setBounds(lastEditorArea);
            editorOwned->setBounds(0,
                                   0,
                                   lastEditorArea.getWidth(),
                                   lastEditorArea.getHeight());
        }
        if (resizeCorner != nullptr)
        {
            resizeCorner->setBounds(
                getWidth() - kResizeHandleSize - 6,
                getHeight() - kResizeHandleSize - 6,
                kResizeHandleSize,
                kResizeHandleSize);
        }
    }

    void mouseDown(const juce::MouseEvent &event) override
    {
        if (_headerBounds().contains(event.getPosition()))
            dragger.startDraggingComponent(&owner, event);
    }

    void mouseDrag(const juce::MouseEvent &event) override
    {
        if (_headerBounds().contains(event.getMouseDownPosition()))
            dragger.dragComponent(&owner, event, nullptr);
    }

private:
    juce::Rectangle<int> _headerBounds() const noexcept
    {
        return getLocalBounds().removeFromTop(kHeaderHeight);
    }

    juce::Component &owner;
    std::function<void()> onCloseFn;
    std::unique_ptr<juce::AudioProcessorEditor> editorOwned;
    juce::Component editorViewport;
    juce::Label titleLabel;
    juce::TextButton optionsButton;
    juce::TextButton closeButton;
    std::unique_ptr<juce::ResizableCornerComponent> resizeCorner;
    juce::ComponentDragger dragger;
    std::function<void()> onToggleDetachFn;
    juce::Rectangle<int> lastEditorArea;
    int naturalEditorWidth = 0;
    int naturalEditorHeight = 0;
    float editorScale = 1.0f;
    bool isDetached = false;
};

inline HostedPluginEditorWindow::HostedPluginEditorWindow(
    const juce::String &title,
    juce::AudioProcessorEditor *editor,
    juce::AudioProcessor *parameterProcessorIn,
    HostedPluginEditorMetadata metadataIn,
    bool showInitially,
    OnClose onClose)
    : juce::DocumentWindow(title,
                           juce::Colours::transparentBlack,
                           0,
                           false),
      metadata(metadataIn),
      parameterProcessor(parameterProcessorIn),
      parameterTouchTracker(parameterProcessorIn),
      onCloseFn(std::move(onClose))
{
    setUsingNativeTitleBar(false);
    setTitleBarHeight(0);
    setName(title);
    editorTitle = title;
    hostContext =
        std::make_unique<HostedPluginEditorHostContext>(metadata, *editor);
    editor->setHostContext(hostContext.get());

    int maxEditorWidth = 1400;
    int maxEditorHeight = 920;
    mixroomResolveHostedPluginEditorMaxSize(maxEditorWidth, maxEditorHeight);
    const int naturalEditorWidth =
        editor->getWidth() > 0 ? editor->getWidth() : 640;
    const int naturalEditorHeight =
        editor->getHeight() > 0 ? editor->getHeight() : 420;
    const bool editorResizable = editor->isResizable();
#if ! JUCE_MAC
    const float nativeViewScale = juce::jmin(
        1.0f,
        juce::jmin((float)maxEditorWidth / (float)naturalEditorWidth,
                   (float)maxEditorHeight / (float)naturalEditorHeight));
#endif
    int initialWidth = naturalEditorWidth;
    int initialHeight = naturalEditorHeight;
#if JUCE_MAC
    if (editorResizable &&
        (initialWidth > maxEditorWidth || initialHeight > maxEditorHeight))
    {
        const float fitScale = juce::jmin(
            1.0f,
            juce::jmin((float)maxEditorWidth / (float)naturalEditorWidth,
                       (float)maxEditorHeight / (float)naturalEditorHeight));
        initialWidth = juce::jmax(
            1, (int)std::round((float)naturalEditorWidth * fitScale));
        initialHeight = juce::jmax(
            1, (int)std::round((float)naturalEditorHeight * fitScale));
        editor->setSize(initialWidth, initialHeight);
    }
#endif
    int minWidth = initialWidth;
    int minHeight = initialHeight;
    int maxWidth = initialWidth;
    int maxHeight = initialHeight;
#if JUCE_MAC
    maxWidth = juce::jmax(maxEditorWidth, initialWidth);
    maxHeight = juce::jmax(maxEditorHeight, initialHeight);
#endif
    if (auto *constrainer = editor->getConstrainer())
    {
        minWidth =
            juce::jmin(initialWidth, juce::jmax(280, constrainer->getMinimumWidth()));
        minHeight =
            juce::jmin(initialHeight, juce::jmax(180, constrainer->getMinimumHeight()));
        maxWidth = constrainer->getMaximumWidth() > 0
                       ? juce::jmax(minWidth, constrainer->getMaximumWidth())
                       : juce::jmax(initialWidth, 1600);
        maxHeight = constrainer->getMaximumHeight() > 0
                        ? juce::jmax(minHeight, constrainer->getMaximumHeight())
                        : juce::jmax(initialHeight, 1200);
        maxWidth = juce::jmin(maxWidth, maxEditorWidth);
        maxHeight = juce::jmin(maxHeight, maxEditorHeight);
        maxWidth = juce::jmax(maxWidth, initialWidth);
        maxHeight = juce::jmax(maxHeight, initialHeight);
    }
    setResizable(
#if JUCE_MAC
        editorResizable,
        editorResizable
#else
        editorResizable,
        editorResizable
#endif
    );

#if JUCE_MAC
    setUsingNativeTitleBar(true);
    setTitleBarHeight(0);
    setTitleBarButtonsRequired(
        juce::DocumentWindow::allButtons,
        true);
    setContentOwned(editor, true);
    setResizeLimits(
        juce::jmin(minWidth, initialWidth),
        juce::jmin(minHeight, initialHeight),
        juce::jmax(maxWidth, initialWidth),
        juce::jmax(maxHeight, initialHeight));
    setContentComponentSize(initialWidth, initialHeight);
    embeddedNativeViewScale = 1.0f;
    attachToDesktopWindowFallback();
#else
    auto *shell = new HostedPluginEditorShell(
        *this,
        getConstrainer(),
        [this]()
        {
            closeButtonPressed();
        },
        [this]()
        {
            setDetached(!detached);
        },
        title,
        editor,
        editorResizable,
        naturalEditorWidth,
        naturalEditorHeight,
        1.0f);
    setContentOwned(shell, true);
    shell->setDetached(detached);
    setResizeLimits(
        editorResizable ? minWidth : initialWidth,
        editorResizable ? minHeight + HostedPluginEditorShell::extraChromeHeight()
                        : initialHeight + HostedPluginEditorShell::extraChromeHeight(),
        editorResizable ? maxWidth : initialWidth,
        editorResizable ? maxHeight + HostedPluginEditorShell::extraChromeHeight()
                        : initialHeight + HostedPluginEditorShell::extraChromeHeight());
    setContentComponentSize(
        initialWidth,
        initialHeight + HostedPluginEditorShell::extraChromeHeight());
    embeddedNativeViewScale = nativeViewScale;
    attachToDesktopWindowFallback();
#endif

#if JUCE_MAC
    juce::Component::SafePointer<HostedPluginEditorWindow> safeThis(this);
    juce::Timer::callAfterDelay(0, [safeThis]()
                                {
        if (safeThis != nullptr)
            safeThis->fitMacNativePluginEditorWindow(); });
    juce::Timer::callAfterDelay(16, [safeThis]()
                                {
        if (safeThis != nullptr)
        {
            safeThis->fitMacNativePluginEditorWindow();
            if (safeThis->isShowing())
                safeThis->toFront(true);
        } });
    juce::Timer::callAfterDelay(60, [safeThis]()
                                {
        if (safeThis != nullptr)
            safeThis->fitMacNativePluginEditorWindow(); });
    juce::Timer::callAfterDelay(220, [safeThis]()
                                {
        if (safeThis != nullptr)
            safeThis->fitMacNativePluginEditorWindow(); });
    juce::Timer::callAfterDelay(500, [safeThis]()
                                {
        if (safeThis != nullptr)
            safeThis->fitMacNativePluginEditorWindow(); });
    juce::Timer::callAfterDelay(1000, [safeThis]()
                                {
        if (safeThis != nullptr)
            safeThis->fitMacNativePluginEditorWindow(); });
#else
    if (showInitially)
        presentFromHost();
#endif

#if JUCE_MAC
    if (showInitially)
    {
        juce::Component::SafePointer<HostedPluginEditorWindow> safeThis(this);
        juce::Timer::callAfterDelay(80, [safeThis]()
                                    {
            if (safeThis != nullptr)
            {
                safeThis->fitMacNativePluginEditorWindow();
                safeThis->presentFromHost();
            } });
    }
#endif
}

inline HostedPluginEditorWindow::~HostedPluginEditorWindow()
{
    releaseEmbeddedNativeChrome();
    if (auto *shell = dynamic_cast<HostedPluginEditorShell *>(getContentComponent()))
    {
        if (auto *editor = shell->getEditor())
            editor->setHostContext(nullptr);
    }
    else if (auto *editor =
                 dynamic_cast<juce::AudioProcessorEditor *>(getContentComponent()))
    {
        editor->setHostContext(nullptr);
    }
}

inline void HostedPluginEditorWindow::setDetached(bool shouldDetach)
{
    if (detached == shouldDetach)
        return;
    detached = shouldDetach;
    if (auto *shell = dynamic_cast<HostedPluginEditorShell *>(getContentComponent()))
        shell->setDetached(detached);
#if JUCE_MAC
    const bool wasVisible = isVisible();
    setVisible(false);
    releaseEmbeddedNativeChrome();
    removeFromDesktop();
    attachToDesktopWindowFallback();
    setVisible(wasVisible);
    toFront(true);
#else
    mixroomSetHostedPluginWindowDetachedForOwner(this, detached);
#endif
}

inline bool HostedPluginEditorWindow::attachToFlutterHostView()
{
#if JUCE_MAC
    if (detached)
        return false;
    void *hostView = mixroomGetFlutterHostNativeView();
    if (hostView == nullptr)
        return false;
    double hostWidth = 0.0;
    double hostHeight = 0.0;
    if (!mixroomGetNativeViewSize(hostView, &hostWidth, &hostHeight))
        return false;

    const int leftInset = 104;
    const int topInset = 54;
    const int rightInset = 28;
    const int bottomInset = 116;
    const int availableWidth = juce::jmax(
        360,
        (int)std::round(hostWidth) - leftInset - rightInset);
    const int availableHeight = juce::jmax(
        260,
        (int)std::round(hostHeight) - topInset - bottomInset);
    const float displayScale = juce::jlimit(
        0.45f,
        1.0f,
        juce::jmin((float)availableWidth / (float)getWidth(),
                   (float)availableHeight / (float)getHeight()));
    embeddedNativeViewScale = displayScale;
    const int displayWidth =
        (int)std::round((float)getWidth() * displayScale);
    const int displayHeight =
        (int)std::round((float)getHeight() * displayScale);

    const int targetX = leftInset + juce::jmax(
        0,
        (int)std::round((availableWidth - displayWidth) * 0.5));
    const int targetY = topInset + juce::jmax(
        0,
        (int)std::round((availableHeight - displayHeight) * 0.5));
    setEmbeddedNativeChromeActive(true);
    setTopLeftPosition(targetX, targetY);
    addToDesktop(getDesktopWindowStyleFlags(), hostView);
    if (auto *peer = getPeer())
    {
        mixroomSetNativeViewFrameScale(peer->getNativeHandle(),
                                       targetX,
                                       targetY,
                                       getWidth(),
                                       getHeight(),
                                       displayScale);
        mixroomConfigureEmbeddedPluginChrome(peer->getNativeHandle(),
                                             editorTitle.toRawUTF8(),
                                             this,
                                             displayScale);
    }
    embeddedInFlutterHostView = true;
    return true;
#else
    return false;
#endif
}

inline void HostedPluginEditorWindow::attachToDesktopWindowFallback()
{
    embeddedInFlutterHostView = false;
    setEmbeddedNativeChromeActive(false);
    setVisible(false);
    centreWithSize(getWidth(), getHeight());
    addToDesktop();
    configureDesktopPeerWindow();
}

inline void HostedPluginEditorWindow::setEmbeddedNativeChromeActive(bool isActive)
{
    if (auto *shell = dynamic_cast<HostedPluginEditorShell *>(getContentComponent()))
        shell->setEmbeddedNativeChromeActive(isActive);
}

inline void HostedPluginEditorWindow::releaseEmbeddedNativeChrome()
{
#if JUCE_MAC
    if (auto *peer = getPeer())
        mixroomReleaseEmbeddedPluginChrome(peer->getNativeHandle());
#endif
}

inline void HostedPluginEditorWindow::configureDesktopPeerWindow()
{
    auto *directEditor =
        dynamic_cast<juce::AudioProcessorEditor *>(getContentComponent());
    if (auto *peer = getPeer())
        mixroomConfigureHostedPluginWindow(
            peer->getNativeHandle(),
            static_cast<int>(metadata.scope),
            metadata.row,
            metadata.effectIndex,
            metadata.clipId,
            this,
            dynamic_cast<HostedPluginEditorShell *>(getContentComponent()) != nullptr,
            directEditor != nullptr && directEditor->isResizable());
}

inline void HostedPluginEditorWindow::fitMacNativePluginEditorWindow()
{
#if JUCE_MAC
    auto *editor =
        dynamic_cast<juce::AudioProcessorEditor *>(getContentComponent());
    if (editor == nullptr)
        return;

    int maxEditorWidth = 1400;
    int maxEditorHeight = 920;
    mixroomResolveHostedPluginEditorMaxSize(maxEditorWidth, maxEditorHeight);

    int targetWidth = editor->getWidth();
    int targetHeight = editor->getHeight();
    if (targetWidth <= 0 || targetHeight <= 0)
        return;

    const bool needsScale =
        targetWidth > maxEditorWidth || targetHeight > maxEditorHeight;
    if (needsScale && editor->isResizable())
    {
        const float fitScale = juce::jlimit(
            0.1f,
            1.0f,
            juce::jmin((float)maxEditorWidth / (float)juce::jmax(1, targetWidth),
                       (float)maxEditorHeight / (float)juce::jmax(1, targetHeight)));
        targetWidth = juce::jmax(
            1, (int)std::round((float)targetWidth * fitScale));
        targetHeight = juce::jmax(
            1, (int)std::round((float)targetHeight * fitScale));
        editor->setSize(targetWidth, targetHeight);
    }

    {
        int minWidth = 280;
        int minHeight = 180;
        int maxWidth = maxEditorWidth;
        int maxHeight = maxEditorHeight;
        if (auto *constrainer = editor->getConstrainer())
        {
            minWidth = juce::jmax(minWidth, constrainer->getMinimumWidth());
            minHeight = juce::jmax(minHeight, constrainer->getMinimumHeight());
            if (constrainer->getMaximumWidth() > 0)
                maxWidth = juce::jmin(maxWidth, constrainer->getMaximumWidth());
            if (constrainer->getMaximumHeight() > 0)
                maxHeight = juce::jmin(maxHeight, constrainer->getMaximumHeight());
        }
        maxWidth = juce::jmax(maxWidth, targetWidth);
        maxHeight = juce::jmax(maxHeight, targetHeight);
        minWidth = juce::jmin(minWidth, targetWidth);
        minHeight = juce::jmin(minHeight, targetHeight);
        setResizeLimits(minWidth, minHeight, maxWidth, maxHeight);
    }

    if (std::abs(targetWidth - getContentComponent()->getWidth()) <= 2 &&
        std::abs(targetHeight - getContentComponent()->getHeight()) <= 2)
        return;

    setContentComponentSize(targetWidth, targetHeight);
    configureDesktopPeerWindow();
#endif
}

inline bool HostedPluginEditorWindow::automationScopeSupported() const noexcept
{
    return metadata.scope == HostedPluginEditorScopeKind::trackEffect ||
           metadata.scope == HostedPluginEditorScopeKind::masterEffect ||
           metadata.scope == HostedPluginEditorScopeKind::midiClip;
}

inline bool HostedPluginEditorWindow::postAutomationRequestForParameterIndex(
    int parameterIndex)
{
    if (!automationScopeSupported())
        return false;
    if (parameterProcessor == nullptr)
        return false;

    juce::String parameterId;
    juce::String parameterName;
    const auto parameters = parameterProcessor->getParameters();
    if (parameterIndex >= 0 && parameterIndex < (int)parameters.size())
    {
        auto *parameter = parameters[(size_t)parameterIndex];
        if (parameter != nullptr)
        {
            parameterId = mixroomParameterIdForAutomation(parameter);
            parameterName = parameter->getName(128).trim();
        }
    }

    mixroomPostHostedPluginAutomationSelection(
        static_cast<int>(metadata.scope),
        metadata.row,
        metadata.effectIndex,
        metadata.clipId,
        parameterId.toRawUTF8(),
        parameterName.toRawUTF8());
    return true;
}

inline bool HostedPluginEditorWindow::requestAutomationForLastTouchedParameter()
{
    return postAutomationRequestForParameterIndex(
        parameterTouchTracker.getLastTouchedParameterIndex());
}

inline bool HostedPluginEditorWindow::showAutomationContextMenuAtContentPoint(
    juce::Point<int> contentPoint)
{
    if (!automationScopeSupported())
        return false;

    auto *shell = dynamic_cast<HostedPluginEditorShell *>(getContentComponent());
    auto *editor = shell != nullptr
                       ? shell->getEditor()
                       : dynamic_cast<juce::AudioProcessorEditor *>(
                             getContentComponent());
    if (editor == nullptr || parameterProcessor == nullptr)
        return false;
    if (shell != nullptr)
    {
        if (!shell->isPointInsideEditor(contentPoint))
            return false;
        contentPoint = shell->contentPointToEditor(contentPoint);
    }
    if (!editor->getLocalBounds().contains(contentPoint))
        return false;
    const auto editorPoint = contentPoint;

    auto *hitComponent = editor->getComponentAt(editorPoint);
    if (hitComponent == nullptr)
        hitComponent = editor;

    int parameterIndex = -1;
    for (auto *candidate = hitComponent;
         candidate != nullptr;
         candidate = candidate == editor ? nullptr : candidate->getParentComponent())
    {
        parameterIndex = editor->getControlParameterIndex(*candidate);
        if (parameterIndex >= 0)
            break;
        if (candidate == editor)
            break;
    }
    juce::String parameterId;
    juce::String parameterName;
    const auto parameters = parameterProcessor->getParameters();
    if (parameterIndex >= 0 && parameterIndex < (int)parameters.size())
    {
        parameterTouchTracker.noteParameterIndex(parameterIndex);
        auto *parameter = parameters[(size_t)parameterIndex];
        if (parameter != nullptr)
        {
            parameterId = mixroomParameterIdForAutomation(parameter);
            parameterName = parameter->getName(128).trim();
        }
    }

    if (automationMenuOpen)
        return true;

    const bool resolvedParameter =
        parameterId.isNotEmpty() && parameterName.isNotEmpty();
    automationMenuOpen = true;
    juce::PopupMenu menu;
    menu.addItem(
        1,
        resolvedParameter
            ? "Automate " + parameterName
            : "Choose Parameter to Automate…");
    const auto screenPoint = editor->localPointToGlobal(editorPoint);
    juce::Component::SafePointer<HostedPluginEditorWindow> safeThis(this);
    menu.showMenuAsync(
        juce::PopupMenu::Options().withTargetScreenArea(
            juce::Rectangle<int>(screenPoint.x, screenPoint.y, 1, 1)),
        [safeThis, parameterId, parameterName, resolvedParameter](int result)
        {
            if (safeThis == nullptr)
                return;
            safeThis->automationMenuOpen = false;
            if (result != 1)
                return;
            mixroomPostHostedPluginAutomationSelection(
                static_cast<int>(safeThis->metadata.scope),
                safeThis->metadata.row,
                safeThis->metadata.effectIndex,
                safeThis->metadata.clipId,
                resolvedParameter ? parameterId.toRawUTF8() : "",
                resolvedParameter ? parameterName.toRawUTF8() : "");
        });
    return true;
}

// ---------------------------
// Helper: simple stereo pan
// ---------------------------
class StereoPanProcessor : public juce::AudioProcessor
{
public:
    StereoPanProcessor()
        : juce::AudioProcessor(
              BusesProperties()
                  .withInput("Input", juce::AudioChannelSet::stereo(), true)
                  .withOutput("Output", juce::AudioChannelSet::stereo(), true))
    {
        addParameter(pan = new juce::AudioParameterFloat(
                         "pan", "Pan",
                         -1.0f, 1.0f, 0.0f)); // -1 = L, 0 = C, 1 = R
    }

    const juce::String getName() const override { return "StereoPanProcessor"; }
    void setAutomationPanNormalizedRealtime(float normalizedPan) noexcept
    {
        const float clamped = juce::jlimit(0.0f, 1.0f, normalizedPan);
        automationPanActual.store(juce::jmap(clamped, -1.0f, 1.0f),
                                  std::memory_order_relaxed);
        automationPanOverrideActive.store(true, std::memory_order_release);
    }
    void clearAutomationPanOverride() noexcept
    {
        automationPanOverrideActive.store(false, std::memory_order_release);
    }

    void prepareToPlay(double sampleRate, int samplesPerBlockExpected) override {}

    void releaseResources() override {}

    void processBlock(juce::AudioBuffer<float> &buffer,
                      juce::MidiBuffer &) override
    {
        const int numChannels = buffer.getNumChannels();
        const int numSamples = buffer.getNumSamples();
        if (numChannels < 2)
            return;

        // Stereo balance law with unity center:
        // p = -1 -> full left, p = 0 -> center (L=1,R=1), p = +1 -> full right.
        // This avoids cumulative -3 dB center drops when multiple pan stages are chained.
        const bool useAutomationPan =
            automationPanOverrideActive.load(std::memory_order_acquire);
        const float p = juce::jlimit(
            -1.0f,
            1.0f,
            useAutomationPan ? automationPanActual.load(std::memory_order_relaxed)
                             : pan->get()); // -1..1
        const float leftGain = (p <= 0.0f) ? 1.0f : (1.0f - p);
        const float rightGain = (p >= 0.0f) ? 1.0f : (1.0f + p);

        auto *left = buffer.getWritePointer(0);
        auto *right = buffer.getWritePointer(1);

        for (int i = 0; i < numSamples; ++i)
        {
            const float l = left[i];
            const float r = right[i];
            left[i] = l * leftGain;
            right[i] = r * rightGain;
        }
    }

    // Boilerplate
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        auto in = layouts.getMainInputChannelSet();
        auto out = layouts.getMainOutputChannelSet();

        if (in.isDisabled() || out.isDisabled())
            return false;

        if (in != out)
            return false;

        // Allow mono or stereo, but they must match
        return in == juce::AudioChannelSet::mono() || in == juce::AudioChannelSet::stereo();
    }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}

    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

    juce::AudioParameterFloat *pan = nullptr;

private:
    std::atomic<bool> automationPanOverrideActive{false};
    std::atomic<float> automationPanActual{0.0f};
};

class MeterTapProcessor : public juce::AudioProcessor
{
public:
    explicit MeterTapProcessor(std::atomic<float> *pL,
                               std::atomic<float> *pR,
                               std::atomic<float> *rL,
                               std::atomic<float> *rR,
                               std::atomic<bool> *enabledFlag)
        : juce::AudioProcessor(
              BusesProperties()
                  .withInput("Input", juce::AudioChannelSet::stereo(), true)
                  .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          peakL(pL), peakR(pR), rmsL(rL), rmsR(rR), enabled(enabledFlag)
    {
    }

    const juce::String getName() const override { return "MeterTapProcessor"; }
    void prepareToPlay(double, int) override {}
    void releaseResources() override {}

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        if (enabled && !enabled->load(std::memory_order_relaxed))
            return;

        const int numCh = buffer.getNumChannels();
        const int numSamples = buffer.getNumSamples();
        if (numCh <= 0 || numSamples <= 0)
            return;

        const float *L = buffer.getReadPointer(0);
        const float *R = numCh > 1 ? buffer.getReadPointer(1) : L;

        float pkL = 0.0f, pkR = 0.0f;
        double ssL = 0.0, ssR = 0.0;

        for (int i = 0; i < numSamples; ++i)
        {
            const float l = L[i];
            const float r = R[i];
            const float al = std::abs(l);
            const float ar = std::abs(r);

            if (al > pkL)
                pkL = al;
            if (ar > pkR)
                pkR = ar;

            ssL += (double)l * (double)l;
            ssR += (double)r * (double)r;
        }

        const float rmL = (float)std::sqrt(ssL / (double)numSamples);
        const float rmR = (float)std::sqrt(ssR / (double)numSamples);

        // smoothing (slightly slower than your master, looks nicer in mini meters)
        constexpr float alpha = 0.18f;
        auto smooth = [alpha](float prev, float next)
        { return prev + alpha * (next - prev); };

        if (peakL && peakR && rmsL && rmsR)
        {
            const float prevPkL = peakL->load(std::memory_order_relaxed);
            const float prevPkR = peakR->load(std::memory_order_relaxed);
            const float prevRmL = rmsL->load(std::memory_order_relaxed);
            const float prevRmR = rmsR->load(std::memory_order_relaxed);

            peakL->store(smooth(prevPkL, pkL), std::memory_order_relaxed);
            peakR->store(smooth(prevPkR, pkR), std::memory_order_relaxed);
            rmsL->store(smooth(prevRmL, rmL), std::memory_order_relaxed);
            rmsR->store(smooth(prevRmR, rmR), std::memory_order_relaxed);
        }
    }

    void setMeterTargets(std::atomic<float> *pL,
                         std::atomic<float> *pR,
                         std::atomic<float> *rL,
                         std::atomic<float> *rR)
    {
        peakL = pL;
        peakR = pR;
        rmsL = rL;
        rmsR = rR;
    }

    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        const auto in = layouts.getMainInputChannelSet();
        const auto out = layouts.getMainOutputChannelSet();
        return in == out &&
               (in == juce::AudioChannelSet::mono() ||
                in == juce::AudioChannelSet::stereo());
    }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

private:
    std::atomic<float> *peakL = nullptr;
    std::atomic<float> *peakR = nullptr;
    std::atomic<float> *rmsL = nullptr;
    std::atomic<float> *rmsR = nullptr;
    std::atomic<bool> *enabled = nullptr;
};

// ---------------------------
// Helper: volume automation
// ---------------------------
struct AutomationPoint
{
    double timeMs = 0.0; // X value in milliseconds
    float value = 0.75f; // Y value (0.0 – 1.0 gain) (0.75 = unity-ish)
};

class VolumeAutomationProcessor : public juce::AudioProcessor
{
public:
    VolumeAutomationProcessor()
        : juce::AudioProcessor(
              BusesProperties()
                  .withInput("Input", juce::AudioChannelSet::stereo(), true)
                  .withOutput("Output", juce::AudioChannelSet::stereo(), true))
    {
        pointsSnapshotRaw.store(pointsSnapshot.get(), std::memory_order_relaxed);
    }
    ~VolumeAutomationProcessor() override = default;

    //==============================================================================
    const juce::String getName() const override { return "VolumeAutomationProcessor"; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    //==============================================================================
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}

    //==============================================================================
    void prepareToPlay(double sampleRate, int /*samplesPerBlockExpected*/) override
    {
        currentSampleRate = sampleRate;
    }

    void releaseResources() override {}

    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        auto in = layouts.getMainInputChannelSet();
        auto out = layouts.getMainOutputChannelSet();

        if (in.isDisabled() || out.isDisabled())
            return false;

        if (in != out)
            return false;

        // Allow mono or stereo tracks
        return in == juce::AudioChannelSet::mono() || in == juce::AudioChannelSet::stereo();
    }

    //==============================================================================
    void processBlock(juce::AudioBuffer<float> &buffer,
                      juce::MidiBuffer &) override
    {
        const int numSamples = buffer.getNumSamples();
        const int numChannels = buffer.getNumChannels();

        if (currentSampleRate <= 0.0)
            return;

        if (audioRenderGenerationPtr == nullptr)
            fallbackRenderGeneration.fetch_add(1, std::memory_order_acq_rel);

        const auto *localPoints = pointsSnapshotRaw.load(std::memory_order_acquire);
        if (localPoints == nullptr || localPoints->empty())
            return;

        // --- Transport (atomic) ---
        double startMs = 0.0;
        if (blockTransportStartSecPtr)
            startMs = blockTransportStartSecPtr->load(std::memory_order_relaxed) * 1000.0;

        const double stepMs = 1000.0 / currentSampleRate;

        for (int sample = 0; sample < numSamples; ++sample)
        {
            const double tMs = startMs + stepMs * sample;
            const float g = getGainAt(*localPoints, tMs);

            for (int ch = 0; ch < numChannels; ++ch)
                buffer.getWritePointer(ch)[sample] *= g;
        }

        // advance transport
        const double deltaSec = (double)numSamples / currentSampleRate;
    }

    //==============================================================================
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    //==============================================================================
    void getStateInformation(juce::MemoryBlock &destData) override {}
    void setStateInformation(const void *data, int sizeInBytes) override {}

    //==============================================================================
    // Public API for UI
    void setAutomationPoints(const std::vector<AutomationPoint> &newPoints)
    {
        auto nextPoints = std::make_shared<std::vector<AutomationPoint>>(newPoints);
        std::sort(nextPoints->begin(), nextPoints->end(),
                  [](const AutomationPoint &a, const AutomationPoint &b)
                  { return a.timeMs < b.timeMs; });
        publishAutomationPoints(
            std::static_pointer_cast<const std::vector<AutomationPoint>>(nextPoints));
    }

    void clearAutomation()
    {
        publishAutomationPoints(std::make_shared<const std::vector<AutomationPoint>>());
    }

    void setBlockTransportPtr(std::atomic<double> *ptr) { blockTransportStartSecPtr = ptr; }
    void setAudioRenderGenerationPtr(std::atomic<uint64_t> *ptr) { audioRenderGenerationPtr = ptr; }

private:
    //==============================================================================
    float getGainAt(const std::vector<AutomationPoint> &pts, double timeMs) const
    {
        if (pts.empty())
            return 1.0f;

        if (timeMs <= pts.front().timeMs)
            return mapValueToGain(pts.front().value);

        if (timeMs >= pts.back().timeMs)
            return mapValueToGain(pts.back().value);

        // binary search
        int lo = 0, hi = (int)pts.size() - 1;
        while (hi - lo > 1)
        {
            int mid = (lo + hi) / 2;
            if (timeMs < pts[mid].timeMs)
                hi = mid;
            else
                lo = mid;
        }

        const auto &p0 = pts[lo];
        const auto &p1 = pts[hi];

        const double t = juce::jlimit(0.0, 1.0,
                                      (timeMs - p0.timeMs) / (p1.timeMs - p0.timeMs));

        float v = (float)juce::jmap(t, (double)p0.value, (double)p1.value);
        return mapValueToGain(v);
    }

    // Your nonlinear gain mapper
    float mapValueToGain(float v) const
    {
        if (v >= 0.75f)
        {
            float t = (v - 0.75f) / 0.25f;
            return juce::jmap(t, 1.0f, 2.0f);
        }
        else
        {
            float t = v / 0.75f;
            return juce::jmap(t, 0.0f, 1.0f);
        }
    }

    //==============================================================================
    struct RetiredAutomationPointSnapshot
    {
        std::shared_ptr<const std::vector<AutomationPoint>> snapshot;
        uint64_t retiredAtRenderGeneration = 0;
    };

    uint64_t currentRenderGeneration() const noexcept
    {
        if (audioRenderGenerationPtr != nullptr)
            return audioRenderGenerationPtr->load(std::memory_order_acquire);
        return fallbackRenderGeneration.load(std::memory_order_acquire);
    }

    void drainRetiredAutomationPointSnapshots()
    {
        constexpr uint64_t kRetireAfterRenderGenerations = 16;
        const uint64_t currentGeneration = currentRenderGeneration();
        for (auto it = retiredPointSnapshots.begin(); it != retiredPointSnapshots.end();)
        {
            const bool renderGraceElapsed =
                currentGeneration >= it->retiredAtRenderGeneration &&
                (currentGeneration - it->retiredAtRenderGeneration) >=
                    kRetireAfterRenderGenerations;
            if (!renderGraceElapsed)
            {
                ++it;
                continue;
            }

            it = retiredPointSnapshots.erase(it);
        }
    }

    void publishAutomationPoints(
        std::shared_ptr<const std::vector<AutomationPoint>> nextPoints)
    {
        if (nextPoints == nullptr)
            nextPoints = std::make_shared<const std::vector<AutomationPoint>>();

        if (pointsSnapshot != nullptr)
        {
            retiredPointSnapshots.push_back(
                {std::move(pointsSnapshot), currentRenderGeneration()});
        }

        pointsSnapshot = std::move(nextPoints);
        pointsSnapshotRaw.store(pointsSnapshot.get(), std::memory_order_release);
        drainRetiredAutomationPointSnapshots();
    }

    std::shared_ptr<const std::vector<AutomationPoint>> pointsSnapshot =
        std::make_shared<const std::vector<AutomationPoint>>();
    std::atomic<const std::vector<AutomationPoint> *> pointsSnapshotRaw{nullptr};
    std::vector<RetiredAutomationPointSnapshot> retiredPointSnapshots;
    std::atomic<uint64_t> fallbackRenderGeneration{0};

    double currentSampleRate = 44100.0;

    std::atomic<double> *blockTransportStartSecPtr = nullptr;
    std::atomic<uint64_t> *audioRenderGenerationPtr = nullptr;
};

#if JUCE_MAC && !JUCE_IOS
class MacIndependentMonitorSourceProcessor final : public juce::AudioProcessor
{
public:
    explicit MacIndependentMonitorSourceProcessor(
        MacIndependentMonitorBuffer &sourceBuffer)
        : juce::AudioProcessor(
              BusesProperties().withOutput(
                  "Output", juce::AudioChannelSet::stereo(), true)),
          buffer(sourceBuffer)
    {
    }

    const juce::String getName() const override
    {
        return "MacIndependentMonitorSourceProcessor";
    }
    void prepareToPlay(double, int) override {}
    void releaseResources() override {}
    void processBlock(juce::AudioBuffer<float> &audio,
                      juce::MidiBuffer &) override
    {
        buffer.read(audio);
    }
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        return layouts.getMainInputChannelSet().isDisabled() &&
            layouts.getMainOutputChannelSet() == juce::AudioChannelSet::stereo();
    }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

private:
    MacIndependentMonitorBuffer &buffer;
};
#endif

// dummy node before a track/row (so it can easily switch next nodes)
class TrackInputProcessor : public juce::AudioProcessor
{
public:
    TrackInputProcessor()
        : juce::AudioProcessor(
              BusesProperties()
                  .withInput("Input", juce::AudioChannelSet::stereo(), true)
                  .withOutput("Output", juce::AudioChannelSet::stereo(), true))
    {
    }

    const juce::String getName() const override { return "TrackInputProcessor"; }

    void prepareToPlay(double /*sampleRate*/, int samplesPerBlockExpected) override
    {
        if (routedClipSource.load(std::memory_order_relaxed) != nullptr)
            prepareScratchBuffer(samplesPerBlockExpected);
    }

    void releaseResources() override
    {
        scratchMidi.clear();
    }

    void processBlock(juce::AudioBuffer<float> &buffer,
                      juce::MidiBuffer &midi) override
    {
        auto *source = routedClipSource.load(std::memory_order_acquire);
        const int targetRowId = rowId.load(std::memory_order_relaxed);
        const void *schedule = routedClipSchedule.load(std::memory_order_acquire);
        if (source == nullptr || targetRowId < 0)
            return;

        if (buffer.getNumSamples() > scratchCapacitySamples ||
            scratchChannelData[0] == nullptr ||
            scratchChannelData[1] == nullptr)
        {
            jassertfalse;
            return;
        }

        scratchView.setDataToReferTo(
            scratchChannelData.data(),
            2,
            buffer.getNumSamples());
        if (source != nullptr && targetRowId >= 0)
        {
            source->processRoutedClipsForRow(
                targetRowId,
                schedule,
                buffer,
                midi,
                scratchView,
                scratchMidi);
        }
    }

    void setRoutedClipSource(RoutedClipSource *source, int targetRowId) noexcept
    {
        rowId.store(targetRowId, std::memory_order_relaxed);
        routedClipSource.store(source, std::memory_order_release);
    }

    void setRoutedRowId(int targetRowId) noexcept
    {
        rowId.store(targetRowId, std::memory_order_relaxed);
    }

    void setRoutedClipSchedule(const void *schedule) noexcept
    {
        routedClipSchedule.store(schedule, std::memory_order_release);
    }

    // Boilerplate
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        auto in = layouts.getMainInputChannelSet();
        auto out = layouts.getMainOutputChannelSet();

        if (in.isDisabled() || out.isDisabled())
            return false;

        if (in != out)
            return false;

        // Track buses: mono or stereo, but must match
        return in == juce::AudioChannelSet::mono() || in == juce::AudioChannelSet::stereo();
    }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}

    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

private:
    void prepareScratchBuffer(int samplesPerBlockExpected)
    {
        juce::ignoreUnused(samplesPerBlockExpected);
        scratchCapacitySamples = kMixroomRealtimeScratchMaxSamples;
        scratchBuffer.setSize(
            2,
            scratchCapacitySamples,
            false,
            false,
            true);
        scratchChannelData[0] = scratchBuffer.getWritePointer(0);
        scratchChannelData[1] = scratchBuffer.getWritePointer(1);
        scratchView.setDataToReferTo(
            scratchChannelData.data(),
            2,
            scratchCapacitySamples);
        scratchMidi.clear();
    }

    std::atomic<RoutedClipSource *> routedClipSource{nullptr};
    std::atomic<int> rowId{-1};
    std::atomic<const void *> routedClipSchedule{nullptr};
    juce::AudioBuffer<float> scratchBuffer;
    juce::AudioBuffer<float> scratchView;
    std::array<float *, 2> scratchChannelData{{nullptr, nullptr}};
    juce::MidiBuffer scratchMidi;
    int scratchCapacitySamples = 0;
};

// ---------------------------
// FilePlayerProcessor
// ---------------------------
class FilePlayerProcessor : public juce::AudioProcessor
{
public:
    FilePlayerProcessor(std::shared_ptr<DecodedClipAudioAsset> decodedSource,
                        const juce::File &file)
        : juce::AudioProcessor(BusesProperties()
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          sourceFile(file)
    {
        decodedAudio = std::move(decodedSource);
        fileSampleRate =
            decodedAudio != nullptr && decodedAudio->sampleRate > 0.0
                ? decodedAudio->sampleRate
                : 44100.0;

        if (decodedAudio != nullptr && decodedAudio->audio.getNumSamples() > 0)
        {
            totalLength = decodedAudio->audio.getNumSamples();
            auto memorySource = std::make_unique<juce::MemoryAudioSource>(
                decodedAudio->audio,
                false,
                false);
            readerSource = memorySource.get();
            resampler = std::make_unique<juce::ResamplingAudioSource>(
                memorySource.release(), true /* delete input */);
        }
    }

    void prepareToPlay(double deviceSampleRate, int samplesPerBlock) override
    {
        if (resampler)
        {
            const double ratio = fileSampleRate / deviceSampleRate;
            resampler->setResamplingRatio(ratio);
            resampler->prepareToPlay(samplesPerBlock, deviceSampleRate);
        }

        setPlayConfigDetails(0, 2, deviceSampleRate, samplesPerBlock);
    }

    void releaseResources() override
    {
        if (resampler)
            resampler->releaseResources();
    }

    void reset() override
    {
        if (readerSource)
            readerSource->setNextReadPosition(0);

        if (resampler)
            resampler->flushBuffers();
    }

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        buffer.clear();

        if (resampler)
        {
            juce::AudioSourceChannelInfo info(&buffer, 0, buffer.getNumSamples());
            resampler->getNextAudioBlock(info);
        }
    }

    void setPosition(double seconds)
    {
        if (readerSource)
            readerSource->setNextReadPosition(
                (juce::int64)(seconds * fileSampleRate));

        if (resampler)
            resampler->flushBuffers();
    }

    double getCurrentPosition() const
    {
        if (!readerSource)
            return 0.0;

        return (double)readerSource->getNextReadPosition() / fileSampleRate;
    }

    double getTotalLengthSeconds() const
    {
        return (double)totalLength / fileSampleRate;
    }

    double getSampleRate() const { return fileSampleRate; }
    const juce::File &getSourceFile() const { return sourceFile; }
    juce::int64 getTotalLength() const { return totalLength; }

    // Boilerplate
    const juce::String getName() const override { return "FilePlayerProcessor"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}
    bool isBusesLayoutSupported(const BusesLayout &) const override { return true; }
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

private:
    std::shared_ptr<DecodedClipAudioAsset> decodedAudio;
    juce::PositionableAudioSource *readerSource = nullptr; // non-owning
    std::unique_ptr<juce::ResamplingAudioSource> resampler;

    juce::File sourceFile;
    juce::int64 totalLength = 0;
    double fileSampleRate = 44100.0;
};

// ---------------------------
// TimelineClipProcessor (NEW)
// - outputs silence outside [clipStartSec, clipEndSec)
// - reads contiguous audio only for the overlap of this block
// - uses engine-provided block transport start time (atomic)
// ---------------------------
struct TimelineMidiNote
{
    juce::String noteId;
    int pitch = 60;
    double startBeat = 0.0;
    double lengthBeats = 1.0;
    double velocity = 0.8;
};

enum class LiveMidiPanicMode : std::uint8_t
{
    liveOnly = 1,
    full = 3,
};

class TimelineClipProcessorBase
{
public:
    virtual ~TimelineClipProcessorBase() = default;
    virtual void setTimeline(double startSec, double lengthSec, double inFileOffsetSec = 0.0) = 0;
    virtual void setMuted(bool m) = 0;
    virtual void setGainUi(float gainUi) = 0;
    virtual void setExtraGainLinear(float gainLinear) = 0;
    virtual void setPanNormalized(float panNormalized) = 0;
    virtual void setFades(double fadeInSec, double fadeOutSec, int fadeCurve) = 0;
    virtual void setPitchSemitones(float semitones) = 0;
    virtual void setReversed(bool shouldReverse) = 0;
    virtual void setStretchOptions(double tempoRatio, bool preservePitch) = 0;
    virtual void primeForOfflineRender() = 0;
    virtual void requestLiveMidiPanic(LiveMidiPanicMode) noexcept {}
};

inline float mixroomUiGainToLinear(float gainUi)
{
    const float userGain = std::clamp(gainUi,
                                      SimpleGainProcessor::kUiMin,
                                      SimpleGainProcessor::kUiMax);
    float db = 0.0f;

    if (userGain <= SimpleGainProcessor::kUiUnity)
    {
        const float t = (SimpleGainProcessor::kUiUnity <= SimpleGainProcessor::kUiMin)
                            ? 0.0f
                            : (userGain - SimpleGainProcessor::kUiMin) /
                                  (SimpleGainProcessor::kUiUnity - SimpleGainProcessor::kUiMin);
        db = SimpleGainProcessor::kDbMin +
             ((0.0f - SimpleGainProcessor::kDbMin) * std::clamp(t, 0.0f, 1.0f));
    }
    else
    {
        const float t = (SimpleGainProcessor::kUiMax <= SimpleGainProcessor::kUiUnity)
                            ? 0.0f
                            : (userGain - SimpleGainProcessor::kUiUnity) /
                                  (SimpleGainProcessor::kUiMax - SimpleGainProcessor::kUiUnity);
        db = (SimpleGainProcessor::kDbMax - 0.0f) * std::clamp(t, 0.0f, 1.0f);
    }

    return (db <= SimpleGainProcessor::kDbMin + 0.001f)
               ? 0.0f
               : std::pow(10.0f, db / 20.0f);
}

inline void applyMixroomGainAndPan(juce::AudioBuffer<float> &buffer,
                                   float gainUi,
                                   float panNormalized,
                                   float extraGainLinear = 1.0f)
{
    const int numChannels = buffer.getNumChannels();
    if (numChannels <= 0)
        return;

    const float linearGain = mixroomUiGainToLinear(gainUi) *
                             std::clamp(extraGainLinear, 0.0f, 64.0f);
    if (linearGain <= 0.0f)
    {
        buffer.clear();
        return;
    }

    buffer.applyGain(linearGain);

    if (numChannels < 2)
        return;

    const float p = std::clamp(panNormalized, -1.0f, 1.0f);
    const float leftGain = (p <= 0.0f) ? 1.0f : (1.0f - p);
    const float rightGain = (p >= 0.0f) ? 1.0f : (1.0f + p);
    auto *left = buffer.getWritePointer(0);
    auto *right = buffer.getWritePointer(1);
    const int numSamples = buffer.getNumSamples();
    for (int i = 0; i < numSamples; ++i)
    {
        left[i] *= leftGain;
        right[i] *= rightGain;
    }
}

inline void applyMixroomClipFades(juce::AudioBuffer<float> &buffer,
                                  double firstTimelineSec,
                                  double sampleRate,
                                  double clipStartSec,
                                  double clipLengthSec,
                                  double fadeInSec,
                                  double fadeOutSec,
                                  int fadeCurve)
{
    const int numSamples = buffer.getNumSamples();
    const int numChannels = buffer.getNumChannels();
    if (numSamples <= 0 || numChannels <= 0 || sampleRate <= 0.0)
        return;

    const double safeFadeIn = juce::jlimit(0.0, clipLengthSec, fadeInSec);
    const double safeFadeOut = juce::jlimit(0.0, clipLengthSec, fadeOutSec);
    if (safeFadeIn <= 1.0e-6 && safeFadeOut <= 1.0e-6)
        return;
    const int safeCurve = juce::jlimit(0, 2, fadeCurve);
    auto shapeFadeIn = [safeCurve](double t)
    {
        t = juce::jlimit(0.0, 1.0, t);
        if (safeCurve == 1)
            return std::sin(t * juce::MathConstants<double>::pi * 0.5);
        if (safeCurve == 2)
        {
            const double s = t * t * (3.0 - (2.0 * t));
            return std::sin(s * juce::MathConstants<double>::pi * 0.5);
        }
        return t;
    };
    auto shapeFadeOut = [safeCurve, &shapeFadeIn](double t)
    {
        t = juce::jlimit(0.0, 1.0, t);
        if (safeCurve == 1 || safeCurve == 2)
            return shapeFadeIn(t);
        return t;
    };

    for (int i = 0; i < numSamples; ++i)
    {
        const double localSec = (firstTimelineSec + ((double)i / sampleRate)) - clipStartSec;
        double gain = 1.0;
        if (safeFadeIn > 1.0e-6 && localSec < safeFadeIn)
            gain = std::min(gain, shapeFadeIn(localSec / safeFadeIn));
        if (safeFadeOut > 1.0e-6 && localSec > clipLengthSec - safeFadeOut)
            gain = std::min(gain, shapeFadeOut((clipLengthSec - localSec) / safeFadeOut));
        const float g = (float)juce::jlimit(0.0, 1.0, gain);
        if (g >= 0.9999f)
            continue;
        for (int ch = 0; ch < numChannels; ++ch)
            buffer.getWritePointer(ch)[i] *= g;
    }
}

class OfflineStaticAudioClipProcessor : public juce::AudioProcessor, public TimelineClipProcessorBase
{
public:
    OfflineStaticAudioClipProcessor(std::shared_ptr<DecodedClipAudioAsset> decodedSource,
                                    const juce::File &file,
                                    std::atomic<double> *blockTransportStartSecPtr,
                                    std::atomic<double> *hostSampleRatePtr,
                                    std::atomic<bool> *isPlayingPtr)
        : juce::AudioProcessor(BusesProperties()
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          sourceFile(file),
          decodedAudio(std::move(decodedSource)),
          blockTransportStartSec(blockTransportStartSecPtr),
          hostSampleRate(hostSampleRatePtr),
          isPlaying(isPlayingPtr)
    {
        if (decodedAudio != nullptr)
        {
            totalLength = decodedAudio->audio.getNumSamples();
            fileSampleRate =
                decodedAudio->sampleRate > 0.0 ? decodedAudio->sampleRate : 44100.0;
        }
    }

    void setTimeline(double startSec, double lengthSec, double inFileOffsetSec = 0.0) override
    {
        clipStartSec.store(startSec, std::memory_order_relaxed);
        clipLengthSec.store(lengthSec, std::memory_order_relaxed);
        fileOffsetSec.store(inFileOffsetSec, std::memory_order_relaxed);
    }

    void setMuted(bool m) override { muted.store(m, std::memory_order_relaxed); }
    void setGainUi(float gainUi) override
    {
        clipGainUi.store(std::clamp(gainUi,
                                    SimpleGainProcessor::kUiMin,
                                    SimpleGainProcessor::kUiMax),
                         std::memory_order_relaxed);
    }
    void setExtraGainLinear(float gainLinear) override
    {
        clipExtraGainLinear.store(std::clamp(gainLinear, 0.0f, 64.0f),
                                  std::memory_order_relaxed);
    }
    void setPanNormalized(float panNormalized) override
    {
        clipPanNormalized.store(std::clamp(panNormalized, -1.0f, 1.0f),
                                std::memory_order_relaxed);
    }
    void setFades(double fadeInSec, double fadeOutSec, int fadeCurve) override
    {
        clipFadeInSec.store(juce::jmax(0.0, fadeInSec), std::memory_order_relaxed);
        clipFadeOutSec.store(juce::jmax(0.0, fadeOutSec), std::memory_order_relaxed);
        clipFadeCurve.store(juce::jlimit(0, 2, fadeCurve), std::memory_order_relaxed);
    }
    void setPitchSemitones(float semitones) override
    {
        juce::ignoreUnused(semitones);
    }
    void setReversed(bool shouldReverse) override
    {
        juce::ignoreUnused(shouldReverse);
    }
    void setStretchOptions(double tempoRatio, bool preservePitch) override
    {
        juce::ignoreUnused(tempoRatio, preservePitch);
    }

    void prepareToPlay(double deviceSampleRate, int samplesPerBlock) override
    {
        if (hostSampleRate)
            hostSampleRate->store(deviceSampleRate, std::memory_order_relaxed);
        setPlayConfigDetails(0, 2, deviceSampleRate, samplesPerBlock);
    }

    void releaseResources() override {}
    void reset() override {}
    void primeForOfflineRender() override {}

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        buffer.clear();

        if (muted.load(std::memory_order_relaxed))
            return;
        if (decodedAudio == nullptr || blockTransportStartSec == nullptr || hostSampleRate == nullptr)
            return;
        if (isPlaying != nullptr && !isPlaying->load(std::memory_order_relaxed))
            return;

        const double sr = hostSampleRate->load(std::memory_order_relaxed);
        if (sr <= 0.0 || fileSampleRate <= 0.0 || totalLength <= 0)
            return;

        const int numSamples = buffer.getNumSamples();
        if (numSamples <= 0)
            return;

        const double blockStart = blockTransportStartSec->load(std::memory_order_relaxed);
        const double blockEnd = blockStart + (double)numSamples / sr;
        const double cs = clipStartSec.load(std::memory_order_relaxed);
        const double cl = clipLengthSec.load(std::memory_order_relaxed);
        const double ce = cs + cl;

        if (blockEnd <= cs || blockStart >= ce)
            return;

        const int writeStart = juce::jlimit(
            0, numSamples,
            (int)std::ceil((cs - blockStart) * sr));
        const int writeEnd = juce::jlimit(
            0, numSamples,
            (int)std::ceil((ce - blockStart) * sr));
        const int framesToRead = juce::jmax(0, writeEnd - writeStart);
        if (framesToRead <= 0)
            return;

        const double inFile = fileOffsetSec.load(std::memory_order_relaxed);
        temp.setSize(2, framesToRead, false, false, true);
        temp.clear();

        for (int ch = 0; ch < juce::jmin(2, temp.getNumChannels()); ++ch)
        {
            const float *src = decodedAudio->audio.getReadPointer(
                juce::jmin(ch, decodedAudio->audio.getNumChannels() - 1));
            float *dst = temp.getWritePointer(ch);

            for (int i = 0; i < framesToRead; ++i)
            {
                const double timelineSec =
                    blockStart + ((double)(writeStart + i) / sr);
                const double sourceFrame =
                    (inFile + (timelineSec - cs)) * fileSampleRate;
                const int frameIndex = juce::jlimit(
                    0,
                    juce::jmax(0, (int)totalLength - 1),
                    (int)std::floor(sourceFrame));
                const int nextFrameIndex =
                    juce::jmin(frameIndex + 1, juce::jmax(0, (int)totalLength - 1));
                const float frac = (float)juce::jlimit(
                    0.0,
                    1.0,
                    sourceFrame - (double)frameIndex);
                dst[i] = src[frameIndex] + ((src[nextFrameIndex] - src[frameIndex]) * frac);
            }
        }

        applyMixroomGainAndPan(temp,
                               clipGainUi.load(std::memory_order_relaxed),
                               clipPanNormalized.load(std::memory_order_relaxed),
                               clipExtraGainLinear.load(std::memory_order_relaxed));
        applyMixroomClipFades(temp,
                              blockStart + ((double)writeStart / sr),
                              sr,
                              cs,
                              cl,
                              clipFadeInSec.load(std::memory_order_relaxed),
                              clipFadeOutSec.load(std::memory_order_relaxed),
                              clipFadeCurve.load(std::memory_order_relaxed));

        for (int ch = 0; ch < juce::jmin(2, buffer.getNumChannels()); ++ch)
            buffer.copyFrom(ch, writeStart, temp, ch, 0, framesToRead);
    }

    const juce::String getName() const override { return "OfflineStaticAudioClipProcessor"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        const auto out = layouts.getMainOutputChannelSet();
        return out == juce::AudioChannelSet::mono() ||
               out == juce::AudioChannelSet::stereo();
    }
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

private:
    juce::File sourceFile;
    std::shared_ptr<DecodedClipAudioAsset> decodedAudio;
    juce::AudioBuffer<float> temp;
    juce::int64 totalLength = 0;
    double fileSampleRate = 44100.0;
    std::atomic<double> *blockTransportStartSec = nullptr;
    std::atomic<double> *hostSampleRate = nullptr;
    std::atomic<bool> *isPlaying = nullptr;
    std::atomic<double> clipStartSec{0.0};
    std::atomic<double> clipLengthSec{0.0};
    std::atomic<double> fileOffsetSec{0.0};
    std::atomic<float> clipGainUi{SimpleGainProcessor::kUiUnity};
    std::atomic<float> clipExtraGainLinear{1.0f};
    std::atomic<float> clipPanNormalized{0.0f};
    std::atomic<double> clipFadeInSec{0.0};
    std::atomic<double> clipFadeOutSec{0.0};
    std::atomic<int> clipFadeCurve{0};
    std::atomic<bool> muted{false};
};

class TimelineClipProcessor : public juce::AudioProcessor, public TimelineClipProcessorBase
{
public:
    TimelineClipProcessor(std::shared_ptr<DecodedClipAudioAsset> decodedSource,
                          const juce::File &file,
                          std::atomic<double> *blockTransportStartSecPtr,
                          std::atomic<double> *hostSampleRatePtr,
                          std::atomic<bool> *isPlayingPtr)
        : juce::AudioProcessor(BusesProperties()
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          sourceFile(file),
          blockTransportStartSec(blockTransportStartSecPtr),
          hostSampleRate(hostSampleRatePtr),
          isPlaying(isPlayingPtr)
    {
        decodedAudio = std::move(decodedSource);
        fileSampleRate =
            decodedAudio != nullptr && decodedAudio->sampleRate > 0.0
                ? decodedAudio->sampleRate
                : 44100.0;
        if (decodedAudio != nullptr && decodedAudio->audio.getNumSamples() > 0)
            totalLength = decodedAudio->audio.getNumSamples();
    }

    // --- timeline API (JUCE owns clip times) ---
    void setTimeline(double startSec, double lengthSec, double inFileOffsetSec = 0.0) override
    {
        clipStartSec.store(startSec, std::memory_order_relaxed);
        clipLengthSec.store(lengthSec, std::memory_order_relaxed);
        fileOffsetSec.store(inFileOffsetSec, std::memory_order_relaxed);
    }

    void setMuted(bool m) override { muted.store(m, std::memory_order_relaxed); }
    void setGainUi(float gainUi) override
    {
        clipGainUi.store(std::clamp(gainUi,
                                    SimpleGainProcessor::kUiMin,
                                    SimpleGainProcessor::kUiMax),
                         std::memory_order_relaxed);
    }
    void setExtraGainLinear(float gainLinear) override
    {
        clipExtraGainLinear.store(std::clamp(gainLinear, 0.0f, 64.0f),
                                  std::memory_order_relaxed);
    }
    void setPanNormalized(float panNormalized) override
    {
        clipPanNormalized.store(std::clamp(panNormalized, -1.0f, 1.0f),
                                std::memory_order_relaxed);
    }
    void setFades(double fadeInSec, double fadeOutSec, int fadeCurve) override
    {
        clipFadeInSec.store(juce::jmax(0.0, fadeInSec), std::memory_order_relaxed);
        clipFadeOutSec.store(juce::jmax(0.0, fadeOutSec), std::memory_order_relaxed);
        clipFadeCurve.store(juce::jlimit(0, 2, fadeCurve), std::memory_order_relaxed);
    }
    void setPitchSemitones(float semitones) override
    {
        pitchSemitones.store(juce::jlimit(-24.0f, 24.0f, semitones),
                             std::memory_order_relaxed);
    }
    void setReversed(bool shouldReverse) override
    {
        reversed.store(shouldReverse, std::memory_order_relaxed);
    }
    void setStretchOptions(double tempoRatio, bool preservePitch) override
    {
        tempoPlaybackRatio.store(juce::jlimit(0.05, 20.0, tempoRatio),
                                 std::memory_order_relaxed);
        preserveTempoPitch.store(preservePitch, std::memory_order_relaxed);
    }

    void prepareToPlay(double deviceSampleRate, int samplesPerBlock) override
    {
        if (hostSampleRate)
            hostSampleRate->store(deviceSampleRate, std::memory_order_relaxed);

        const int scratchSamples =
            juce::jmax(samplesPerBlock, kMixroomRealtimeScratchMaxSamples);
        tempCapacitySamples = scratchSamples;
        temp.setSize(2, scratchSamples, false, false, true);
        tempChannelData[0] = temp.getWritePointer(0);
        tempChannelData[1] = temp.getWritePointer(1);
        tempView.setDataToReferTo(tempChannelData.data(), 2, scratchSamples);
        if (pitchCompensator)
        {
            pitchCompensator->prepareToPlay(deviceSampleRate, samplesPerBlock);
            if (auto *mix = pitchCompensator->parameters.getRawParameterValue("mix"))
                mix->store(100.0f, std::memory_order_relaxed);
        }

        setPlayConfigDetails(0, 2, deviceSampleRate, samplesPerBlock);
    }

    void releaseResources() override
    {
        if (pitchCompensator)
            pitchCompensator->releaseResources();
    }

    void reset() override
    {
        if (pitchCompensator)
            pitchCompensator->reset();
    }

    void primeForOfflineRender() override
    {
        reset();
    }

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        buffer.clear();

        if (muted.load(std::memory_order_relaxed))
            return;

        if (decodedAudio == nullptr || !blockTransportStartSec || !hostSampleRate)
            return;

        if (isPlaying != nullptr && !isPlaying->load(std::memory_order_relaxed))
            return;

        const double sr = hostSampleRate->load(std::memory_order_relaxed);
        if (sr <= 0.0)
            return;

        const int numSamples = buffer.getNumSamples();

        const double blockStart = blockTransportStartSec->load(std::memory_order_relaxed);
        const double blockEnd = blockStart + (double)numSamples / sr;

        const double cs = clipStartSec.load(std::memory_order_relaxed);
        const double cl = clipLengthSec.load(std::memory_order_relaxed);
        const double ce = cs + cl;

        // no overlap => silence
        if (blockEnd <= cs || blockStart >= ce)
            return;

        // Convert clip overlap to integer sample bounds in this block.
        // Use ceil for both bounds to avoid sample holes/overlaps from float truncation.
        const int writeStart = juce::jlimit(
            0, numSamples,
            (int)std::ceil((cs - blockStart) * sr));
        const int writeEnd = juce::jlimit(
            0, numSamples,
            (int)std::ceil((ce - blockStart) * sr));

        const int framesToRead = juce::jmax(0, writeEnd - writeStart);
        if (framesToRead <= 0)
            return;
        if (framesToRead > tempCapacitySamples)
        {
            jassertfalse;
            return;
        }

        // Convert exact write start sample back to timeline, then to file position.
        // This keeps block-to-block reads sample-consistent when clip positions shift.
        const double inFile = fileOffsetSec.load(std::memory_order_relaxed);
        const double readTimelineStart = blockStart + ((double)writeStart / sr);
        const bool shouldReverse = reversed.load(std::memory_order_relaxed);
        const double requestedPitch = requestedPitchShiftSemitones();
        const bool needsPitchProcessing = std::abs(requestedPitch) >= 0.01;

        juce::AudioBuffer<float> outputView;
        std::array<float *, 2> outputChannelData{{nullptr, nullptr}};
        juce::AudioBuffer<float> *renderBuffer = nullptr;
        if (needsPitchProcessing)
        {
            tempView.setDataToReferTo(tempChannelData.data(), 2, framesToRead);
            tempView.clear();
            renderBuffer = &tempView;
        }
        else
        {
            const int outputChannels = juce::jmin(2, buffer.getNumChannels());
            if (outputChannels <= 0)
                return;
            for (int ch = 0; ch < outputChannels; ++ch)
                outputChannelData[(size_t)ch] = buffer.getWritePointer(ch, writeStart);
            outputView.setDataToReferTo(outputChannelData.data(), outputChannels, framesToRead);
            outputView.clear();
            renderBuffer = &outputView;
        }

        if (!renderDecodedBlock(
                *renderBuffer,
                framesToRead,
                sr,
                readTimelineStart,
                cs,
                ce,
                inFile,
                shouldReverse))
            return;

        if (needsPitchProcessing)
            applyPitchShiftSemitones(*renderBuffer, requestedPitch);
        applyMixroomGainAndPan(*renderBuffer,
                               clipGainUi.load(std::memory_order_relaxed),
                               clipPanNormalized.load(std::memory_order_relaxed),
                               clipExtraGainLinear.load(std::memory_order_relaxed));
        applyMixroomClipFades(*renderBuffer,
                              readTimelineStart,
                              sr,
                              cs,
                              cl,
                              clipFadeInSec.load(std::memory_order_relaxed),
                              clipFadeOutSec.load(std::memory_order_relaxed),
                              clipFadeCurve.load(std::memory_order_relaxed));

        if (needsPitchProcessing)
        {
            for (int ch = 0; ch < juce::jmin(2, buffer.getNumChannels()); ++ch)
                buffer.copyFrom(ch, writeStart, *renderBuffer, ch, 0, framesToRead);
        }
    }

    // boilerplate
    const juce::String getName() const override { return "TimelineClipProcessor"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}
    bool isBusesLayoutSupported(const BusesLayout &) const override { return true; }
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

private:
    double getTempoPlaybackRatio() const
    {
        return juce::jlimit(0.05, 20.0,
                            tempoPlaybackRatio.load(std::memory_order_relaxed));
    }

    static float sampleDecodedCubic(const float *source,
                                    int totalSamples,
                                    double frame) noexcept
    {
        if (source == nullptr || totalSamples <= 0)
            return 0.0f;
        if (totalSamples == 1)
            return source[0];
        if (frame < 0.0 || frame > (double)(totalSamples - 1))
            return 0.0f;

        frame = juce::jlimit(0.0, (double)(totalSamples - 1), frame);
        const int i1 = juce::jlimit(0, totalSamples - 1, (int)std::floor(frame));
        const int i0 = juce::jmax(0, i1 - 1);
        const int i2 = juce::jmin(totalSamples - 1, i1 + 1);
        const int i3 = juce::jmin(totalSamples - 1, i1 + 2);
        const float t = (float)(frame - (double)i1);

        const float y0 = source[i0];
        const float y1 = source[i1];
        const float y2 = source[i2];
        const float y3 = source[i3];
        const float a0 = (-0.5f * y0) + (1.5f * y1) - (1.5f * y2) + (0.5f * y3);
        const float a1 = y0 - (2.5f * y1) + (2.0f * y2) - (0.5f * y3);
        const float a2 = (-0.5f * y0) + (0.5f * y2);
        return (((a0 * t) + a1) * t + a2) * t + y1;
    }

    void applyPitchShiftSemitones(juce::AudioBuffer<float> &buffer, double semitones)
    {
        if (!pitchCompensator)
            return;

        if (std::abs(semitones) < 0.01)
            return;

        // The built-in shifter is ±12 st per pass; split larger shifts.
        const int passes = juce::jlimit(
            1, 8, (int)std::ceil(std::abs(semitones) / 12.0));
        const float semitonesPerPass = (float)(semitones / (double)passes);

        if (auto *mix = pitchCompensator->parameters.getRawParameterValue("mix"))
            mix->store(100.0f, std::memory_order_relaxed);
        if (auto *semitonesParam =
                pitchCompensator->parameters.getRawParameterValue("semitones"))
            semitonesParam->store(
                juce::jlimit(-12.0f, 12.0f, semitonesPerPass),
                std::memory_order_relaxed);

        pitchMidiScratch.clear();
        for (int i = 0; i < passes; ++i)
            pitchCompensator->processBlock(buffer, pitchMidiScratch);
    }

    double requestedPitchShiftSemitones() const
    {
        double requestedSemitones =
            (double)pitchSemitones.load(std::memory_order_relaxed);

        if (preserveTempoPitch.load(std::memory_order_relaxed))
        {
            const double tempoRatio = getTempoPlaybackRatio();
            if (tempoRatio > 0.0)
            {
                // Cancel pitch drift caused by tempo resampling when preserve mode is enabled.
                requestedSemitones +=
                    -12.0 * (std::log(tempoRatio) / std::log(2.0));
            }
        }

        return juce::jlimit(-96.0, 96.0, requestedSemitones);
    }

    bool renderDecodedBlock(juce::AudioBuffer<float> &destination,
                            int framesToRender,
                            double deviceSampleRate,
                            double readTimelineStart,
                            double clipStartSec,
                            double clipEndSec,
                            double inFileOffsetSec,
                            bool shouldReverse)
    {
        if (decodedAudio == nullptr || deviceSampleRate <= 0.0 || framesToRender <= 0)
            return false;

        const int decodedSamples = decodedAudio->audio.getNumSamples();
        const int decodedChannels = decodedAudio->audio.getNumChannels();
        if (decodedSamples <= 0 || decodedChannels <= 0)
            return false;

        const double speedRatio = getTempoPlaybackRatio();
        const int renderChannels = juce::jmin(2, destination.getNumChannels());
        for (int ch = 0; ch < renderChannels; ++ch)
        {
            const int sourceChannel = juce::jmin(ch, decodedChannels - 1);
            const float *source = decodedAudio->audio.getReadPointer(sourceChannel);
            float *dest = destination.getWritePointer(ch);
            for (int i = 0; i < framesToRender; ++i)
            {
                const double timelineSec =
                    readTimelineStart + ((double)i / deviceSampleRate);
                double sourceSec = 0.0;
                if (shouldReverse)
                    sourceSec =
                        inFileOffsetSec +
                        (juce::jmax(0.0, clipEndSec - timelineSec) * speedRatio);
                else
                    sourceSec =
                        inFileOffsetSec +
                        (juce::jmax(0.0, timelineSec - clipStartSec) * speedRatio);

                double sourceFrame = sourceSec * fileSampleRate;
                if (shouldReverse)
                    sourceFrame -= 1.0;
                dest[i] = sampleDecodedCubic(source, decodedSamples, sourceFrame);
            }
        }

        return true;
    }

    std::shared_ptr<DecodedClipAudioAsset> decodedAudio;
    std::unique_ptr<PitchShiftAudioProcessor> pitchCompensator{
        std::make_unique<PitchShiftAudioProcessor>()};
    juce::MidiBuffer pitchMidiScratch;

    juce::AudioBuffer<float> temp;
    juce::AudioBuffer<float> tempView;
    std::array<float *, 2> tempChannelData{{nullptr, nullptr}};
    int tempCapacitySamples = 0;

    juce::File sourceFile;
    juce::int64 totalLength = 0;
    double fileSampleRate = 44100.0;

    std::atomic<double> *blockTransportStartSec = nullptr;
    std::atomic<double> *hostSampleRate = nullptr;
    std::atomic<bool> *isPlaying = nullptr;

    std::atomic<double> clipStartSec{0.0};
    std::atomic<double> clipLengthSec{0.0};
    std::atomic<double> fileOffsetSec{0.0};
    std::atomic<float> clipGainUi{SimpleGainProcessor::kUiUnity};
    std::atomic<float> clipExtraGainLinear{1.0f};
    std::atomic<float> clipPanNormalized{0.0f};
    std::atomic<double> clipFadeInSec{0.0};
    std::atomic<double> clipFadeOutSec{0.0};
    std::atomic<int> clipFadeCurve{0};
    std::atomic<float> pitchSemitones{0.0f};
    std::atomic<bool> reversed{false};
    std::atomic<double> tempoPlaybackRatio{1.0};
    std::atomic<bool> preserveTempoPitch{false};
    std::atomic<bool> muted{false};
};

class TimelineMidiClipProcessor : public juce::AudioProcessor, public TimelineClipProcessorBase
{
public:
    struct DecodedSamplePcm
    {
        int sampleRate = 48000;
        std::vector<float> left;
        std::vector<float> right;
        float peak = 1.0f;

        int frameCount() const
        {
            return (int)juce::jmin(left.size(), right.size());
        }
    };

    struct PreparedLiveSample
    {
        PreparedLiveSample()
            : sampled(false),
              sampledMidiPitch(60),
              keyCenter(60),
              gainLinear(1.0),
              attackSec(0.005),
              releaseSec(0.35),
              pitchKeytrack(100.0),
              pitchOffsetSemitones(0.0),
              startFrame(0),
              endFrameExclusive(0),
              oneShot(false)
        {
        }

        bool sampled;
        int sampledMidiPitch;
        std::shared_ptr<const DecodedSamplePcm> source;
        int keyCenter;
        double gainLinear;
        double attackSec;
        double releaseSec;
        double pitchKeytrack;
        double pitchOffsetSemitones;
        int startFrame;
        int endFrameExclusive;
        bool oneShot;
    };

    static void setFlutterAssetRootPath(const juce::String &rootPath)
    {
        const juce::ScopedLock lock(flutterAssetRootLock());
        flutterAssetRoot() = rootPath.trim();
    }

    TimelineMidiClipProcessor(std::atomic<double> *blockTransportStartSecPtr,
                              std::atomic<double> *hostSampleRatePtr,
                              std::atomic<bool> *isPlayingPtr)
        : juce::AudioProcessor(BusesProperties()
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          blockTransportStartSec(blockTransportStartSecPtr),
          hostSampleRate(hostSampleRatePtr),
          isPlaying(isPlayingPtr)
    {
        for (std::size_t i = 0; i < kLiveMidiEventQueueCapacity; ++i)
            liveMidiEventQueue[i].sequence.store(i, std::memory_order_relaxed);
        liveMidiBlockEvents.fill({});
        activeLiveNotes.reserve(kMaxActiveLiveNotes);
        blockNoteIndices.reserve(kMaxTimelineMidiNotes);
        blockNotePitches.reserve(kMaxTimelineMidiNotes);
        blockNoteEndSourceSecs.reserve(kMaxTimelineMidiNotes);
        timelineRegions.reserve(kMaxTimelineMidiNotes);
    }

    void setTimeline(double startSec, double lengthSec, double inFileOffsetSec = 0.0) override
    {
        clipStartSec.store(startSec, std::memory_order_relaxed);
        clipLengthSec.store(lengthSec, std::memory_order_relaxed);
        fileOffsetSec.store(inFileOffsetSec, std::memory_order_relaxed);
    }

    void setMuted(bool m) override { muted.store(m, std::memory_order_relaxed); }
    void setGainUi(float gainUi) override
    {
        clipGainUi.store(std::clamp(gainUi,
                                    SimpleGainProcessor::kUiMin,
                                    SimpleGainProcessor::kUiMax),
                         std::memory_order_relaxed);
    }
    void setExtraGainLinear(float gainLinear) override
    {
        clipExtraGainLinear.store(std::clamp(gainLinear, 0.0f, 64.0f),
                                  std::memory_order_relaxed);
    }
    void setPanNormalized(float panNormalized) override
    {
        clipPanNormalized.store(std::clamp(panNormalized, -1.0f, 1.0f),
                                std::memory_order_relaxed);
    }

    void setFades(double fadeInSec, double fadeOutSec, int fadeCurve) override
    {
        juce::ignoreUnused(fadeInSec, fadeOutSec, fadeCurve);
    }

    void setPitchSemitones(float semitones) override
    {
        pitchSemitones.store(juce::jlimit(-24.0f, 24.0f, semitones),
                             std::memory_order_relaxed);
    }

    void setReversed(bool shouldReverse) override
    {
        juce::ignoreUnused(shouldReverse);
    }

    void setStretchOptions(double tempoRatio, bool preservePitch) override
    {
        tempoPlaybackRatio.store(juce::jlimit(0.05, 20.0, tempoRatio),
                                 std::memory_order_relaxed);
        preserveTempoPitch.store(preservePitch, std::memory_order_relaxed);
    }

    void setMidiData(const juce::Array<TimelineMidiNote> &notes,
                     const juce::String &instrumentId,
                     const juce::String &instrumentName,
                     const juce::NamedValueSet &params,
                     double sourceTempoBpm)
    {
        auto next = std::make_shared<PendingState>();
        next->notes = notes;
        next->renderNotes.reserve((size_t)juce::jmin((int)kMaxTimelineMidiNotes, notes.size()));
        for (const auto &note : notes)
        {
            if (next->renderNotes.size() >= kMaxTimelineMidiNotes)
                break;

            TimelineMidiNote n;
            n.pitch = juce::jlimit(0, 127, note.pitch);
            n.startBeat = juce::jmax(0.0, note.startBeat);
            n.lengthBeats = juce::jmax(0.03125, note.lengthBeats);
            n.velocity = juce::jlimit(0.0, 1.0, note.velocity);
        next->renderNotes.push_back(n);
        }
        next->instrumentId = instrumentId;
        next->instrumentName = instrumentName;
        next->usesDrumKitSamplePitchMap =
            usesDrumKitSamplePitchMap(instrumentId);
        next->sourceTempoBpm = juce::jlimit(1.0, 400.0, sourceTempoBpm);
        next->sampledDefinition = prepareSampledDefinitionForNotes(
            resolveSampledDefinition(instrumentId, instrumentName),
            next->notes,
            next->usesDrumKitSamplePitchMap);
        next->sampledAttackOverride =
            params.contains(juce::Identifier("attackMs"));
        next->sampledReleaseOverride =
            params.contains(juce::Identifier("releaseMs"));

        next->preset = resolvePreset(instrumentId, instrumentName);
        if (next->sampledDefinition != nullptr &&
            !next->sampledDefinition->regions.empty())
        {
            next->preset.family = InstrumentFamily::sampled;
            next->preset.attackMs = next->sampledDefinition->defaultAttackSec * 1000.0;
            next->preset.releaseMs = next->sampledDefinition->defaultReleaseSec * 1000.0;
            next->preset.outputGain = 0.72;
            next->preset.drive = 0.0;
            next->preset.noise = 0.0;
        }
        applyParamOverrides(next->preset, params);

        std::shared_ptr<const PendingState> immutableState = std::move(next);
        const auto *immutableStateRaw = immutableState.get();
        auto previousState = std::atomic_exchange_explicit(
            &publishedState,
            immutableState,
            std::memory_order_acq_rel);
        if (previousState != nullptr)
        {
            retiredStates.push_back(
                {std::move(previousState), renderGeneration.load(std::memory_order_acquire)});
        }
        publishedStateRaw.store(immutableStateRaw, std::memory_order_release);
        drainRetiredStates();
    }

    static bool canResolveSampledInstrument(const juce::String &instrumentId,
                                            const juce::String &instrumentName)
    {
        const juce::String assetPath =
            sfzAssetPathForInstrument(instrumentId, instrumentName);
        if (assetPath.isEmpty())
            return true;

        const auto definition = sampledDefinitionForAsset(assetPath);
        return definition != nullptr && !definition->regions.empty();
    }

    static bool prepareSampledInstrumentAssets(const juce::String &instrumentId,
                                               const juce::String &instrumentName,
                                               const juce::Array<TimelineMidiNote> &notes)
    {
        const juce::String assetPath =
            sfzAssetPathForInstrument(instrumentId, instrumentName);
        if (assetPath.isEmpty())
            return true;

        const auto definition = sampledDefinitionForAsset(assetPath);
        if (definition == nullptr || definition->regions.empty())
            return false;

        preloadSampledRegionsForNotes(
            *definition,
            notes,
            usesDrumKitSamplePitchMap(instrumentId));
        return true;
    }

    bool enqueueLiveMidiEvent(bool noteOn,
                              int channel,
                              int pitch,
                              float velocity,
                              const PreparedLiveSample &preparedSample = {})
    {
        LiveMidiEvent event;
        event.noteOn = noteOn;
        event.channel = juce::jlimit(1, 16, channel);
        event.pitch = juce::jlimit(0, 127, pitch);
        event.velocity = juce::jlimit(0.0f, 1.0f, velocity);
        event.preparedSample = preparedSample;
        return enqueueLiveMidiEventLockFree(event);
    }

    void requestLiveMidiPanic(LiveMidiPanicMode mode) noexcept override
    {
        liveMidiPanicRequest.fetch_or(
            static_cast<std::uint8_t>(mode),
            std::memory_order_release);
    }

    bool prepareLiveMidiSample(int pitch,
                               float velocity,
                               PreparedLiveSample &preparedSample)
    {
        preparedSample = {};
        auto state = std::atomic_load_explicit(
            &publishedState,
            std::memory_order_acquire);
        if (state == nullptr)
            return false;
        if (state->sampledDefinition == nullptr ||
            state->sampledDefinition->regions.empty())
            return true;

        const int sampledPitch =
            sampledMidiPitchForDrumMap(
                state->usesDrumKitSamplePitchMap,
                pitch);
        const int lowKey =
            juce::jlimit(0, 127, (int)std::round(state->preset.sampleLowKey));
        const int highKey =
            juce::jlimit(lowKey, 127, (int)std::round(state->preset.sampleHighKey));
        if (sampledPitch < lowKey || sampledPitch > highKey)
            return false;

        const int midiVelocity = juce::jlimit(
            0,
            127,
            (int)std::lround(juce::jlimit(0.0f, 1.0f, velocity) * 127.0f));
        const int sequenceStep =
            liveSamplePrepareSequenceCounter.fetch_add(1, std::memory_order_relaxed);
        const SampledRegion *region = pickSampledRegion(
            *state->sampledDefinition,
            sampledPitch,
            midiVelocity,
            sequenceStep);
        if (region == nullptr || region->sampleAssetPath.trim().isEmpty())
            return false;

        auto sample = decodedSampleForAsset(region->sampleAssetPath);
        if (sample == nullptr || sample->frameCount() < 2)
            return false;

        SampledRegion loadedRegion = *region;
        loadedRegion.sample = std::move(sample);
        const SampledRegion effectiveRegion =
            samplerRegionForPreset(loadedRegion, state->preset, sampledPitch);
        if (effectiveRegion.sample == nullptr || effectiveRegion.sample->frameCount() < 2)
            return false;

        preparedSample.sampled = true;
        preparedSample.sampledMidiPitch = sampledPitch;
        preparedSample.source = effectiveRegion.sample;
        preparedSample.keyCenter = effectiveRegion.keyCenter;
        preparedSample.gainLinear = effectiveRegion.gainLinear;
        preparedSample.attackSec = effectiveRegion.attackSec;
        preparedSample.releaseSec = effectiveRegion.releaseSec;
        preparedSample.pitchKeytrack = effectiveRegion.pitchKeytrack;
        preparedSample.pitchOffsetSemitones = effectiveRegion.pitchOffsetSemitones;
        preparedSample.startFrame = effectiveRegion.sampleStartFrame;
        preparedSample.endFrameExclusive = effectiveRegion.sampleEndFrameExclusive;
        preparedSample.oneShot = effectiveRegion.oneShot;
        return true;
    }

    void prepareToPlay(double deviceSampleRate, int samplesPerBlock) override
    {
        if (hostSampleRate)
            hostSampleRate->store(deviceSampleRate, std::memory_order_relaxed);
        setPlayConfigDetails(0, 2, deviceSampleRate, samplesPerBlock);
    }

    void releaseResources() override {}

    void reset() override
    {
        LiveMidiEvent dropped;
        while (dequeueLiveMidiEventLockFree(dropped))
        {
        }

        liveMidiPanicRequest.store(0, std::memory_order_relaxed);
        activeLiveNotes.clear();
        activeTimelineNotes.reset();
        cachedStateRaw = nullptr;
        cachedNotes = &emptyCachedNotes;
        cachedInstrumentId.clear();
        cachedUsesDrumKitSamplePitchMap = false;
        cachedSampledDefinition.reset();
        cachedSampledAttackOverride = false;
        cachedSampledReleaseOverride = false;
        cachedSourceTempoBpm = 120.0;
        liveSamplePrepareSequenceCounter.store(0, std::memory_order_relaxed);
        steadyBlockStartSec.store(std::numeric_limits<double>::quiet_NaN(),
                                  std::memory_order_relaxed);
        steadyWasPlaying.store(false, std::memory_order_relaxed);
    }

    void primeForOfflineRender() override
    {
        reset();
        refreshCachedState();
    }

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        renderGeneration.fetch_add(1, std::memory_order_acq_rel);
        buffer.clear();
        applyPendingLiveMidiPanic();

        if (muted.load(std::memory_order_relaxed))
            return;
        if (!blockTransportStartSec || !hostSampleRate)
            return;

        const double sr = hostSampleRate->load(std::memory_order_relaxed);
        if (sr <= 0.0)
            return;

        const bool hostPlaying =
            (isPlaying == nullptr) || isPlaying->load(std::memory_order_relaxed);

        const int numSamples = buffer.getNumSamples();
        const int outChannels = buffer.getNumChannels();
        if (numSamples <= 0 || outChannels <= 0)
            return;

        const double incomingBlockStart =
            blockTransportStartSec->load(std::memory_order_relaxed);
        const double blockDurationSec = (double)numSamples / sr;
        double blockStart = incomingBlockStart;
        bool discontinuity = true;
        const bool previousHostPlaying =
            steadyWasPlaying.exchange(hostPlaying, std::memory_order_relaxed);
        const double expectedBlockStart =
            steadyBlockStartSec.load(std::memory_order_relaxed);

        if (hostPlaying)
        {
            const bool hadExpected = std::isfinite(expectedBlockStart);
            const double continuityToleranceSec =
                juce::jmax(4.0 / sr, 0.002);
            discontinuity =
                !hadExpected ||
                !previousHostPlaying ||
                std::abs(incomingBlockStart - expectedBlockStart) >
                    continuityToleranceSec;
            if (!discontinuity)
                blockStart = expectedBlockStart;

            steadyBlockStartSec.store(blockStart + blockDurationSec,
                                      std::memory_order_relaxed);
        }
        else
        {
            steadyBlockStartSec.store(incomingBlockStart,
                                      std::memory_order_relaxed);
            activeTimelineNotes.reset();
        }

        const double blockEnd = blockStart + blockDurationSec;

        refreshCachedState();
        if (hostPlaying && discontinuity)
            activeTimelineNotes.reset();
        applyPendingLiveMidiEvents();

        const bool sampledMode =
            cachedPreset.family == InstrumentFamily::sampled &&
            cachedSampledDefinition != nullptr &&
            !cachedSampledDefinition->regions.empty();
        const double attackSec = juce::jmax(0.0, cachedPreset.attackMs / 1000.0);
        const double decaySec = juce::jmax(0.0, cachedPreset.decayMs / 1000.0);
        const double sustainLevel = juce::jlimit(0.0, 1.0, cachedPreset.sustainLevel);
        const double releaseSec = juce::jmax(0.0, cachedPreset.releaseMs / 1000.0);
        const float driveGain =
            sampledMode
                ? 1.0f
                : (float)(1.0 + cachedPreset.drive *
                                      (cachedPreset.family == InstrumentFamily::bass ? 3.0 : 5.0));
        const bool stereo = outChannels >= 2;
        auto *outL = buffer.getWritePointer(0);
        auto *outR = stereo ? buffer.getWritePointer(1) : nullptr;

        const bool hasTimelineNotes = hostPlaying && !cachedNotes->empty();
        const bool hasLiveNotes = !activeLiveNotes.empty();
        if (!hasTimelineNotes && !hasLiveNotes)
            return;

        const double speedRatio = getTempoPlaybackRatio();
        const double safeRatio = speedRatio <= 0.0 ? 1.0 : speedRatio;
        const double sourceSecPerBeat = 60.0 / juce::jlimit(1.0, 400.0, cachedSourceTempoBpm);
        if (hasTimelineNotes)
        {
            const double cs = clipStartSec.load(std::memory_order_relaxed);
            const double cl = clipLengthSec.load(std::memory_order_relaxed);
            const double ce = cs + cl;

            if (blockEnd > cs && blockStart < ce)
            {
                const int writeStart = juce::jlimit(
                    0, numSamples, (int)std::ceil((cs - blockStart) * sr));
                const int writeEnd = juce::jlimit(
                    0, numSamples, (int)std::ceil((ce - blockStart) * sr));
                const int framesToRender = juce::jmax(0, writeEnd - writeStart);
                if (framesToRender > 0)
                {
                    const double inFile = fileOffsetSec.load(std::memory_order_relaxed);
                    const double startTimelineSec = blockStart + ((double)writeStart / sr);
                    const double endTimelineSec =
                        startTimelineSec + ((double)framesToRender / sr);
                    const double roundedBlockSourceStartSec =
                        ((startTimelineSec - cs) * safeRatio) + inFile;
                    const double blockSourceStartSec =
                        mixroom::timelineMidiAdmissionSourceStartSec(
                            blockStart,
                            blockEnd,
                            cs,
                            roundedBlockSourceStartSec,
                            inFile);
                    const double blockSourceEndSec =
                        ((endTimelineSec - cs) * safeRatio) + inFile;
                    const double pitchOffsetSemitones =
                        (double)pitchSemitones.load(std::memory_order_relaxed);
                    const bool keepOriginalPitch =
                        preserveTempoPitch.load(std::memory_order_relaxed);
                    const double tempoPitchOffsetSemitones =
                        (!keepOriginalPitch && safeRatio > 0.0)
                            ? 12.0 * (std::log(safeRatio) / std::log(2.0))
                            : 0.0;
                    blockNoteIndices.clear();
                    blockNotePitches.clear();
                    blockNoteEndSourceSecs.clear();
                    timelineRegions.clear();

                    const size_t timelineNoteCount =
                        juce::jmin(cachedNotes->size(), kMaxTimelineMidiNotes);
                    for (size_t noteIndex = 0; noteIndex < timelineNoteCount; ++noteIndex)
                    {
                        const auto &note = (*cachedNotes)[noteIndex];
                        const int notePitchBase = sampledMode
                            ? sampledMidiPitchForDrumMap(
                                  cachedUsesDrumKitSamplePitchMap,
                                  note.pitch)
                            : juce::jlimit(0, 127, note.pitch);
                        const int midiVelocity = juce::jlimit(
                            0,
                            127,
                            (int)std::lround(
                                juce::jlimit(0.0, 1.0, note.velocity) * 127.0));
                        const SampledRegion *sampledRegion =
                            sampledMode
                                ? pickSampledRegion(
                                      *cachedSampledDefinition,
                                      notePitchBase,
                                      midiVelocity,
                                      (int)noteIndex)
                                : nullptr;
                        if (sampledRegion != nullptr &&
                            !isSampledRegionReady(*sampledRegion))
                        {
                            sampledRegion = nullptr;
                        }
                        if (sampledMode && sampledRegion == nullptr)
                            continue;
                        if (sampledMode)
                        {
                            const int lowKey = juce::jlimit(0, 127, (int)std::round(cachedPreset.sampleLowKey));
                            const int highKey = juce::jlimit(lowKey, 127, (int)std::round(cachedPreset.sampleHighKey));
                            if (notePitchBase < lowKey || notePitchBase > highKey)
                                continue;
                        }
                        SampledRegion effectiveRegion;
                        if (sampledRegion != nullptr)
                            effectiveRegion = samplerRegionForPreset(
                                *sampledRegion,
                                cachedPreset,
                                notePitchBase);

                        double noteReleaseSec = releaseSec;
                        if (sampledRegion != nullptr &&
                            !cachedSampledReleaseOverride)
                        {
                            noteReleaseSec =
                                juce::jmax(0.0, effectiveRegion.releaseSec);
                        }

                        const double noteStartSourceSec =
                            note.startBeat * sourceSecPerBeat;
                        double noteLengthSourceSec =
                            juce::jmax(0.001, note.lengthBeats * sourceSecPerBeat);
                        const double notePitchWithOffsets =
                            (double)notePitchBase +
                            pitchOffsetSemitones +
                            tempoPitchOffsetSemitones;
                        if (sampledRegion != nullptr && effectiveRegion.oneShot)
                        {
                            const double oneShotDurationSec =
                                sampledPlayableDurationSec(
                                    effectiveRegion,
                                    notePitchWithOffsets,
                                    sr);
                            noteLengthSourceSec = juce::jmax(
                                noteLengthSourceSec,
                                oneShotDurationSec * safeRatio);
                        }
                        const double noteEndSourceSec =
                            noteStartSourceSec +
                            noteLengthSourceSec +
                            (noteReleaseSec * safeRatio);
                        if (noteEndSourceSec <= blockSourceStartSec)
                        {
                            activeTimelineNotes.reset(noteIndex);
                            continue;
                        }

                        if (noteStartSourceSec >= blockSourceEndSec)
                        {
                            continue;
                        }

                        const bool noteStartsInBlock =
                            noteStartSourceSec >= blockSourceStartSec &&
                            noteStartSourceSec < blockSourceEndSec;
                        const bool noteAlreadyActive =
                            activeTimelineNotes.test(noteIndex);
                        if (!noteStartsInBlock && !noteAlreadyActive)
                            continue;
                        if (noteStartsInBlock)
                            activeTimelineNotes.set(noteIndex);

                        blockNoteIndices.push_back(noteIndex);
                        blockNotePitches.push_back(notePitchBase);
                        blockNoteEndSourceSecs.push_back(noteEndSourceSec);
                        if (sampledMode)
                            timelineRegions.push_back(effectiveRegion);
                    }

                    for (int i = 0; i < framesToRender; ++i)
                    {
                        const double timelineSec = startTimelineSec + ((double)i / sr);
                        const double sourceSec = ((timelineSec - cs) * safeRatio) + inFile;
                        float mixL = 0.0f;
                        float mixR = 0.0f;

                        for (size_t activeIndex = 0; activeIndex < blockNoteIndices.size(); ++activeIndex)
                        {
                            const size_t noteIndex = blockNoteIndices[activeIndex];
                            const auto &note = (*cachedNotes)[noteIndex];
                            const SampledRegion *sampledRegion =
                                sampledMode ? &timelineRegions[activeIndex] : nullptr;
                            const int sampledPitch = blockNotePitches[activeIndex];

                            double noteAttackSec = attackSec;
                            double noteReleaseSec = releaseSec;
                            if (sampledRegion != nullptr)
                            {
                                if (!cachedSampledAttackOverride)
                                    noteAttackSec =
                                        juce::jmax(0.0, sampledRegion->attackSec);
                                if (!cachedSampledReleaseOverride)
                                    noteReleaseSec =
                                        juce::jmax(0.0, sampledRegion->releaseSec);
                            }
                            const double releaseSourceSec = noteReleaseSec * safeRatio;
                            double notePitch =
                                (double)sampledPitch +
                                pitchOffsetSemitones +
                                tempoPitchOffsetSemitones;

                            const double noteStartSourceSec = note.startBeat * sourceSecPerBeat;
                            double noteLengthSourceSec = juce::jmax(0.001, note.lengthBeats * sourceSecPerBeat);
                            if (sampledRegion != nullptr && sampledRegion->oneShot)
                            {
                                const double oneShotDurationSec =
                                    sampledPlayableDurationSec(
                                        *sampledRegion,
                                        notePitch,
                                        sr);
                                noteLengthSourceSec = juce::jmax(
                                    noteLengthSourceSec,
                                    oneShotDurationSec * safeRatio);
                            }
                            const double noteEndSourceSec = noteStartSourceSec + noteLengthSourceSec + releaseSourceSec;
                            if (sourceSec < noteStartSourceSec || sourceSec >= noteEndSourceSec)
                                continue;

                            const double ageSourceSec = sourceSec - noteStartSourceSec;
                            const double ageRealSec = ageSourceSec / safeRatio;
                            const double noteLengthRealSec = noteLengthSourceSec / safeRatio;

                            const double env = envelopeLevel(
                                ageRealSec,
                                noteLengthRealSec,
                                noteAttackSec,
                                decaySec,
                                sustainLevel,
                                noteReleaseSec);

                            if (env <= 0.0)
                                continue;

                            const double totalRealSec = juce::jmax(
                                0.001, noteLengthRealSec + noteReleaseSec);
                            const double noteProgress = juce::jlimit(0.0, 1.0, ageRealSec / totalRealSec);

                            const float velocityGain =
                                (float)juce::jlimit(0.0, 1.0, note.velocity);

                            if (sampledRegion != nullptr)
                            {
                                float sampleL = 0.0f;
                                float sampleR = 0.0f;
                                const bool rendered =
                                    cachedPreset.granularMode >= 0.5
                                        ? renderGranularStereo(
                                              *sampledRegion,
                                              cachedPreset,
                                              notePitch,
                                              ageRealSec,
                                              sr,
                                              (int)(note.pitch * 997 + (int)note.startBeat * 7919),
                                              sampleL,
                                              sampleR)
                                        : renderSampledStereo(
                                              *sampledRegion,
                                              cachedPreset,
                                              notePitch,
                                              ageRealSec,
                                              sr,
                                              sampleL,
                                              sampleR);
                                if (!rendered)
                                {
                                    continue;
                                }

                                const float gain =
                                    (float)env *
                                    velocityGain *
                                    (float)cachedPreset.outputGain *
                                    (float)sampledRegion->gainLinear;
                                mixL += sampleL * gain;
                                mixR += sampleR * gain;
                                continue;
                            }

                            const double freq = 440.0 * std::pow(2.0, (notePitch - 69.0) / 12.0);
                            const int seedBase = (int)(note.pitch * 97 + (int)(note.startBeat * 2000.0) * 13);
                            const int sampleSeed = seedBase + (int)std::floor(ageRealSec * sr);

                            const float raw = renderInstrumentSample(cachedPreset,
                                                                     note.pitch,
                                                                     freq,
                                                                     ageRealSec,
                                                                     noteProgress,
                                                         env,
                                                         sr,
                                                         sampleSeed);
                            const float sampleValue = std::tanh(raw * driveGain) *
                                                      (float)env *
                                                      velocityGain *
                                                      (float)cachedPreset.outputGain;

                            const double pan = juce::jlimit(-0.95, 0.95,
                                                            std::sin((double)note.pitch * 0.23 + note.startBeat * 0.9) * cachedPreset.stereoWidth);
                            const float leftGain = (float)std::sqrt(0.5 * (1.0 - pan));
                            const float rightGain = (float)std::sqrt(0.5 * (1.0 + pan));

                            mixL += sampleValue * leftGain;
                            mixR += sampleValue * rightGain;
                        }

                        mixL = juce::jlimit(-1.0f, 1.0f, mixL);
                        mixR = juce::jlimit(-1.0f, 1.0f, mixR);
                        const int outIndex = writeStart + i;

                        if (stereo)
                        {
                            outL[outIndex] += mixL;
                            outR[outIndex] += mixR;
                        }
                        else
                        {
                            outL[outIndex] += 0.5f * (mixL + mixR);
                        }
                    }

                    for (size_t activeIndex = 0;
                         activeIndex < blockNoteIndices.size() &&
                         activeIndex < blockNoteEndSourceSecs.size();
                         ++activeIndex)
                    {
                        if (blockNoteEndSourceSecs[activeIndex] <= blockSourceEndSec)
                            activeTimelineNotes.reset(blockNoteIndices[activeIndex]);
                    }
                }
            }
        }

        if (activeLiveNotes.empty())
        {
            applyMixroomGainAndPan(buffer,
                                   clipGainUi.load(std::memory_order_relaxed),
                                   clipPanNormalized.load(std::memory_order_relaxed),
                                   clipExtraGainLinear.load(std::memory_order_relaxed));
            return;
        }

        const double invSr = 1.0 / sr;
        for (int i = 0; i < numSamples; ++i)
        {
            float mixL = 0.0f;
            float mixR = 0.0f;

            for (auto &voice : activeLiveNotes)
            {
                const bool voiceSampled =
                    sampledMode && voice.sampledSource != nullptr;
                const double voiceAttackSec =
                    (voiceSampled && !cachedSampledAttackOverride)
                        ? juce::jmax(0.0, voice.sampledAttackSec)
                        : attackSec;
                const double voiceReleaseSec =
                    (voiceSampled && !cachedSampledReleaseOverride)
                        ? juce::jmax(0.0, voice.sampledReleaseSec)
                        : releaseSec;

                double env = 0.0;
                if (!voice.releasing)
                {
                    env = envelopeHoldLevel(
                        voice.ageSec,
                        voiceAttackSec,
                        decaySec,
                        sustainLevel);
                }
                else
                {
                    if (voiceReleaseSec > 0.0)
                    {
                        const double releaseNorm = voice.releaseAgeSec / voiceReleaseSec;
                        env = voice.releaseStartLevel * (1.0 - releaseNorm);
                    }
                }

                if (env <= 0.0)
                {
                    voice.ageSec += invSr;
                    if (voice.releasing)
                        voice.releaseAgeSec += invSr;
                    continue;
                }

                const double noteProgress = voice.releasing
                                                ? juce::jlimit(0.0, 1.0, voice.releaseAgeSec / voiceReleaseSec)
                                                : juce::jlimit(0.0, 0.85, voice.ageSec / juce::jmax(0.08, voiceAttackSec + 0.42));

                double notePitch = (double)voice.pitch + (double)pitchSemitones.load(std::memory_order_relaxed);

                if (voiceSampled)
                {
                    SampledRegion liveRegion;
                    liveRegion.sample = voice.sampledSource;
                    liveRegion.keyCenter = voice.sampledKeyCenter;
                    liveRegion.pitchKeytrack = voice.sampledPitchKeytrack;
                    liveRegion.pitchOffsetSemitones =
                        voice.sampledPitchOffsetSemitones;
                    liveRegion.sampleStartFrame = voice.sampledStartFrame;
                    liveRegion.sampleEndFrameExclusive =
                        voice.sampledEndFrameExclusive;
                    liveRegion.oneShot = voice.sampledOneShot;
                    float sampleL = 0.0f;
                    float sampleR = 0.0f;
                    const double sampledNotePitch =
                        (double)voice.sampledMidiPitch +
                        (double)pitchSemitones.load(std::memory_order_relaxed);
                    const bool rendered =
                        cachedPreset.granularMode >= 0.5
                            ? renderGranularStereo(
                                  liveRegion,
                                  cachedPreset,
                                  sampledNotePitch,
                                  voice.ageSec,
                                  sr,
                                  voice.seedBase,
                                  sampleL,
                                  sampleR)
                            : renderSampledStereo(
                                  liveRegion,
                                  cachedPreset,
                                  sampledNotePitch,
                                  voice.ageSec,
                                  sr,
                                  sampleL,
                                  sampleR);
                    if (!rendered)
                    {
                        voice.releasing = true;
                        voice.releaseAgeSec = voiceReleaseSec;
                        voice.ageSec += invSr;
                        continue;
                    }

                    const float gain =
                        (float)env *
                        (float)voice.velocity *
                        (float)cachedPreset.outputGain *
                        (float)voice.sampledGainLinear;
                    mixL += sampleL * gain;
                    mixR += sampleR * gain;

                    voice.ageSec += invSr;
                    if (voice.releasing)
                        voice.releaseAgeSec += invSr;
                    continue;
                }

                const double freq = 440.0 * std::pow(2.0, (notePitch - 69.0) / 12.0);
                const int sampleSeed = voice.seedBase + (int)std::floor(voice.ageSec * sr);

                const float raw = renderInstrumentSample(cachedPreset,
                                                         voice.pitch,
                                                         freq,
                                                         voice.ageSec,
                                                         noteProgress,
                                                         env,
                                                         sr,
                                                         sampleSeed);
                const float sampleValue = std::tanh(raw * driveGain) *
                                          (float)env *
                                          (float)voice.velocity *
                                          (float)cachedPreset.outputGain;

                const double pan = juce::jlimit(-0.95, 0.95,
                                                std::sin((double)voice.pitch * 0.23 + (double)voice.channel * 0.37) * cachedPreset.stereoWidth);
                const float leftGain = (float)std::sqrt(0.5 * (1.0 - pan));
                const float rightGain = (float)std::sqrt(0.5 * (1.0 + pan));

                mixL += sampleValue * leftGain;
                mixR += sampleValue * rightGain;

                voice.ageSec += invSr;
                if (voice.releasing)
                    voice.releaseAgeSec += invSr;
            }

            mixL = juce::jlimit(-1.0f, 1.0f, mixL);
            mixR = juce::jlimit(-1.0f, 1.0f, mixR);
            if (stereo)
            {
                outL[i] += mixL;
                outR[i] += mixR;
            }
            else
            {
                outL[i] += 0.5f * (mixL + mixR);
            }
        }

        activeLiveNotes.erase(
            std::remove_if(
                activeLiveNotes.begin(),
                activeLiveNotes.end(),
                [sampledMode, releaseSec, this](const ActiveLiveNote &voice)
                {
                    const double voiceReleaseSec =
                        (sampledMode && voice.sampledSource != nullptr &&
                         !cachedSampledReleaseOverride)
                            ? juce::jmax(0.0, voice.sampledReleaseSec)
                            : releaseSec;
                    return voice.releasing && voice.releaseAgeSec >= voiceReleaseSec;
                }),
            activeLiveNotes.end());

        applyMixroomGainAndPan(buffer,
                               clipGainUi.load(std::memory_order_relaxed),
                               clipPanNormalized.load(std::memory_order_relaxed),
                               clipExtraGainLinear.load(std::memory_order_relaxed));
    }

    const juce::String getName() const override { return "TimelineMidiClipProcessor"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}
    bool isBusesLayoutSupported(const BusesLayout &) const override { return true; }
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

private:
    enum class InstrumentFamily
    {
        basic,
        sampled,
        bass,
        pad,
        lead,
        pluck,
        keys,
        brass,
        wavetable,
        harmonic,
        drum,
    };

    struct InstrumentPreset
    {
        InstrumentFamily family = InstrumentFamily::basic;
        int oscillator = 1;
        double cutoffHz = 3200.0;
        double attackMs = 18.0;
        double releaseMs = 180.0;
        double drive = 0.08;
        double outputGain = 0.36;
        double detune = 0.0;
        double stereoWidth = 0.12;
        double tone = 0.55;
        double transient = 0.08;
        double pitchDropSemitones = 0.0;
        double noise = 0.02;
        double padDetuneOffset = 0.008;
        double decayMs = 120.0;
        double sustainLevel = 0.86;
        double sampleStartNorm = 0.0;
        double sampleEndNorm = 1.0;
        double reverseSample = 0.0;
        double normalizeSample = 0.0;
        double samplePlayMode = 0.0;
        double rootNote = 60.0;
        double sampleLowKey = 0.0;
        double sampleHighKey = 127.0;
        double sliceMode = 0.0;
        double sliceCount = 8.0;
        double timeStretchMode = 0.0;
        double sampleFilterCutoffHz = 20000.0;
        double granularMode = 0.0;
        double grainAttackMs = 18.0;
        double grainHoldMs = 42.0;
        double grainSpacingPct = 100.0;
        double waveSpacingPct = 100.0;
        double grainPan = 0.34;
        double grainLfoDepthPct = 0.0;
        double grainLfoSpeedHz = 0.8;
        double grainRandomPct = 0.0;
        double grainTransientMode = 0.0;
        double grainTransientHoldMs = 80.0;
        double grainLoop = 1.0;
        double grainPositionHold = 0.0;
        double grainKeyMode = 0.0;
    };

    struct SampledRegion
    {
        std::shared_ptr<const DecodedSamplePcm> sample;
        juce::String sampleAssetPath;
        int loKey = 0;
        int hiKey = 127;
        int keyCenter = 60;
        int loVel = 0;
        int hiVel = 127;
        double gainLinear = 1.0;
        double attackSec = 0.005;
        double releaseSec = 0.35;
        double pitchKeytrack = 100.0;
        double pitchOffsetSemitones = 0.0;
        int sampleStartFrame = 0;
        int sampleEndFrameExclusive = 0;
        bool oneShot = false;
        int seqLength = 1;
        int seqPosition = 1;
        double loRand = 0.0;
        double hiRand = 1.0;
    };

    struct SampledDefinition
    {
        juce::String sfzAssetPath;
        std::vector<SampledRegion> regions;
        double defaultAttackSec = 0.005;
        double defaultReleaseSec = 0.35;
    };

    struct PendingState
    {
        juce::Array<TimelineMidiNote> notes;
        std::vector<TimelineMidiNote> renderNotes;
        juce::String instrumentId;
        juce::String instrumentName;
        bool usesDrumKitSamplePitchMap = false;
        InstrumentPreset preset;
        std::shared_ptr<const SampledDefinition> sampledDefinition;
        bool sampledAttackOverride = false;
        bool sampledReleaseOverride = false;
        double sourceTempoBpm = 120.0;
    };

    struct LiveMidiEvent
    {
        bool noteOn = false;
        int channel = 1;
        int pitch = 60;
        float velocity = 1.0f;
        PreparedLiveSample preparedSample;
    };

    struct ActiveLiveNote
    {
        int channel = 1;
        int pitch = 60;
        int sampledMidiPitch = 60;
        double velocity = 1.0;
        double ageSec = 0.0;
        bool releasing = false;
        double releaseAgeSec = 0.0;
        double releaseStartLevel = 1.0;
        int seedBase = 0;
        std::shared_ptr<const DecodedSamplePcm> sampledSource;
        int sampledKeyCenter = 60;
        double sampledGainLinear = 1.0;
        double sampledAttackSec = 0.005;
        double sampledReleaseSec = 0.35;
        double sampledPitchKeytrack = 100.0;
        double sampledPitchOffsetSemitones = 0.0;
        int sampledStartFrame = 0;
        int sampledEndFrameExclusive = 0;
        bool sampledOneShot = false;
    };

    static double readParam(const juce::NamedValueSet &params, const char *key, double fallback)
    {
        auto *v = params.getVarPointer(juce::Identifier(key));
        if (v == nullptr || v->isVoid())
            return fallback;
        if (v->isBool())
            return (bool)(*v) ? 1.0 : 0.0;
        if (v->isInt() || v->isInt64() || v->isDouble())
            return (double)(*v);
        return fallback;
    }

    static double hashNoise(int seed)
    {
        uint32_t x = (uint32_t)(seed * 747796405u + 2891336453u);
        x ^= x >> 16;
        x *= 2246822519u;
        x ^= x >> 13;
        x *= 3266489917u;
        x ^= x >> 16;
        const double n01 = (double)(x & 0x00ffffffu) / (double)0x01000000u;
        return (n01 * 2.0) - 1.0;
    }

    static double envelopeHoldLevel(
        double ageSec,
        double attackSec,
        double decaySec,
        double sustainLevel)
    {
        attackSec = juce::jmax(0.0, attackSec);
        decaySec = juce::jmax(0.0, decaySec);
        sustainLevel = juce::jlimit(0.0, 1.0, sustainLevel);
        if (attackSec > 0.0 && ageSec < attackSec)
            return juce::jlimit(0.0, 1.0, ageSec / attackSec);

        const double decayAge = ageSec - attackSec;
        if (decaySec > 0.0 && decayAge < decaySec)
        {
            const double t = decayAge / decaySec;
            return 1.0 + ((sustainLevel - 1.0) * t);
        }
        return sustainLevel;
    }

    static double envelopeLevel(
        double ageSec,
        double holdSec,
        double attackSec,
        double decaySec,
        double sustainLevel,
        double releaseSec)
    {
        if (ageSec < holdSec)
            return envelopeHoldLevel(ageSec, attackSec, decaySec, sustainLevel);

        releaseSec = juce::jmax(0.0, releaseSec);
        if (releaseSec <= 0.0)
            return 0.0;
        const double releaseAge = ageSec - holdSec;
        const double releaseStart =
            envelopeHoldLevel(holdSec, attackSec, decaySec, sustainLevel);
        return releaseStart * (1.0 - (releaseAge / releaseSec));
    }

    static double wrapPhase(double phase)
    {
        phase -= std::floor(phase);
        if (phase < 0.0)
            phase += 1.0;
        return phase;
    }

    static bool usesDrumKitSamplePitchMap(const juce::String &instrumentId)
    {
        const juce::String id = instrumentId.trim().toLowerCase();
        return id == "mixroom.drum_808_starter" ||
               id == "mixroom.drum_house" ||
               id == "mixroom.drum_breakbeat" ||
               id == "mixroom.drum_trap" ||
               id == "sfz.vsco.mixroom_drum_starter" ||
               id == "sfz.vsco.mixroom_dry_drum_kit" ||
               id == "sfz.vsco.mixroom_acoustic_drum_kit" ||
               id == "sfz.vsco.mixroom_electro_punch_kit" ||
               id == "sfz.vsco_2_ce_1_1_0_mixroomdrumstarter" ||
               id == "sfz.vsco_2_ce_1_1_0_mixroomdrydrumkit" ||
               id == "sfz.vsco_2_ce_1_1_0_mixroomacousticdrumkit" ||
               id == "sfz.vsco_2_ce_1_1_0_mixroomelectropunchkit" ||
               id.contains("mixroomdrumstarter.sfz") ||
               id.contains("mixroomdrydrumkit.sfz") ||
               id.contains("mixroomacousticdrumkit.sfz");
    }

    static int sampledMidiPitchForDrumMap(bool usesDrumMap, int pitch)
    {
        const int safePitch = juce::jlimit(0, 127, pitch);
        if (!usesDrumMap)
            return safePitch;

        switch (safePitch)
        {
        case 35:
            return 36;
        case 37:
        case 39:
            return 38;
        case 41:
        case 43:
            return 45;
        case 48:
            return 47;
        case 52:
        case 53:
            return 42;
        case 55:
        case 57:
        case 59:
            return 49;
        default:
            return safePitch;
        }
    }

    static int sampledMidiPitchForInstrument(const juce::String &instrumentId,
                                             int pitch)
    {
        return sampledMidiPitchForDrumMap(
            usesDrumKitSamplePitchMap(instrumentId),
            pitch);
    }

    static float waveFromType(int type, double phase)
    {
        const double p = wrapPhase(phase);
        switch (type)
        {
        case 0:
            return (float)std::sin(juce::MathConstants<double>::twoPi * p);
        case 1:
            return (float)((2.0 * p) - 1.0);
        case 2:
            return p < 0.5 ? 1.0f : -1.0f;
        default:
            return (float)(p < 0.5 ? (-1.0 + 4.0 * p) : (3.0 - 4.0 * p));
        }
    }

    static double softSaturate(double input, double amount)
    {
        const double drive = juce::jmax(1.0, amount);
        const double norm = std::tanh(drive);
        if (norm <= 1.0e-6)
            return input;
        return std::tanh(input * drive) / norm;
    }

    using SfzOpcodeMap = std::unordered_map<std::string, juce::String>;

    struct SfzParsedLine
    {
        juce::String blockTag;
        SfzOpcodeMap opcodes;
    };

    struct SampledAssetCache
    {
        juce::CriticalSection lock;
        std::unordered_map<std::string, std::shared_ptr<const SampledDefinition>> definitions;
        std::unordered_map<std::string, std::shared_ptr<const DecodedSamplePcm>> samples;
        std::deque<std::string> sampleLru;
    };

    static SampledAssetCache &sampledAssetCache()
    {
        static SampledAssetCache cache;
        return cache;
    }

    static juce::String normalizeAssetPath(const juce::String &rawPath)
    {
        juce::String path = rawPath.trim().replaceCharacter('\\', '/');
        while (path.contains("//"))
            path = path.replace("//", "/");
        const bool preserveLeadingSlash =
            juce::File::isAbsolutePath(path) ||
            path.startsWith("./") ||
            path.startsWith("../") ||
            path.startsWithChar('~');
        if (preserveLeadingSlash)
            return path;
        while (path.startsWithChar('/'))
            path = path.substring(1);
        return path;
    }

    static juce::File resolveFlutterAssetFile(const juce::String &assetPathRaw)
    {
        const juce::String raw = assetPathRaw.trim();
        const bool allowDirectPath =
            juce::File::isAbsolutePath(raw) ||
            raw.startsWith("./") ||
            raw.startsWith("../") ||
            raw.startsWithChar('~');
        if (raw.isNotEmpty() && allowDirectPath)
        {
            const juce::File direct(raw);
            if (direct.existsAsFile())
                return direct;
        }

        const juce::String assetPath = normalizeAssetPath(assetPathRaw);
        if (assetPath.isEmpty())
            return {};

        juce::StringArray candidateAssetPaths;
        candidateAssetPaths.addIfNotAlreadyThere(assetPath);
        candidateAssetPaths.addIfNotAlreadyThere(
            assetPath.replace("#", "%23"));

        {
            const juce::ScopedLock lock(flutterAssetRootLock());
            const juce::String rootPath = flutterAssetRoot();
            if (rootPath.isNotEmpty())
            {
                const juce::File root(rootPath);
                for (const auto &candidatePath : candidateAssetPaths)
                {
                    const juce::File rootDirect = root.getChildFile(candidatePath);
                    if (rootDirect.existsAsFile())
                        return rootDirect;

                    const juce::File nested = root.getChildFile("flutter_assets")
                                                  .getChildFile(candidatePath);
                    if (nested.existsAsFile())
                        return nested;
                }
            }
        }

        const juce::File appBundle =
            juce::File::getSpecialLocation(juce::File::currentApplicationFile)
                .getParentDirectory();
        const std::array<juce::File, 4> roots = {
            appBundle.getChildFile("Frameworks")
                .getChildFile("App.framework")
                .getChildFile("flutter_assets"),
            appBundle.getChildFile("flutter_assets"),
            appBundle.getChildFile("Frameworks").getChildFile("App.framework"),
            appBundle};

        for (const auto &root : roots)
        {
            if (!root.exists())
                continue;
            for (const auto &candidatePath : candidateAssetPaths)
            {
                const auto direct = root.getChildFile(candidatePath);
                if (direct.existsAsFile())
                    return direct;

                const auto nested = root.getChildFile("flutter_assets")
                                        .getChildFile(candidatePath);
                if (nested.existsAsFile())
                    return nested;
            }
        }

        return appBundle.getChildFile("Frameworks")
            .getChildFile("App.framework")
            .getChildFile("flutter_assets")
            .getChildFile(assetPath);
    }

    static SfzOpcodeMap parseSfzOpcodes(const juce::String &lineRaw)
    {
        SfzOpcodeMap out;
        const juce::String line =
            lineRaw.upToFirstOccurrenceOf("//", false, false).trim();
        if (line.isEmpty())
            return out;

        static const std::regex pattern("([A-Za-z_][A-Za-z0-9_]*)=");
        const std::string utf8 = line.toStdString();

        std::vector<size_t> matchStarts;
        std::vector<size_t> matchLengths;
        std::vector<std::string> matchKeys;
        for (std::sregex_iterator it(utf8.begin(), utf8.end(), pattern), end;
             it != end; ++it)
        {
            matchStarts.push_back((size_t)it->position());
            matchLengths.push_back((size_t)it->length());
            matchKeys.push_back((*it)[1].str());
        }

        if (matchStarts.empty())
            return out;

        for (size_t i = 0; i < matchStarts.size(); ++i)
        {
            const size_t valueStart = matchStarts[i] + matchLengths[i];
            const size_t valueEnd =
                (i + 1 < matchStarts.size()) ? matchStarts[i + 1] : utf8.size();
            if (valueStart >= valueEnd)
                continue;

            const juce::String key =
                juce::String(matchKeys[i].c_str()).trim().toLowerCase();
            const juce::String value =
                juce::String::fromUTF8(utf8.data() + valueStart,
                                       (int)(valueEnd - valueStart))
                    .trim();
            if (key.isEmpty() || value.isEmpty())
                continue;
            out[key.toStdString()] = value;
        }

        return out;
    }

    static SfzParsedLine parseSfzLine(const juce::String &lineRaw)
    {
        SfzParsedLine out;
        const juce::String line =
            lineRaw.upToFirstOccurrenceOf("//", false, false).trim();
        if (line.isEmpty())
            return out;

        juce::String remainder = line;
        if (line.startsWithChar('<'))
        {
            const int close = line.indexOfChar('>');
            if (close > 1)
            {
                out.blockTag =
                    line.substring(1, close).trim().toLowerCase();
                remainder = line.substring(close + 1).trim();
            }
        }

        if (remainder.isNotEmpty())
            out.opcodes = parseSfzOpcodes(remainder);
        return out;
    }

    static void mergeOpcodeMap(SfzOpcodeMap &dst, const SfzOpcodeMap &src)
    {
        for (const auto &entry : src)
            dst[entry.first] = entry.second;
    }

    static juce::String opcodeValue(const SfzOpcodeMap &values, const char *key)
    {
        if (auto found = values.find(std::string(key)); found != values.end())
            return found->second;
        return {};
    }

    static double readSfzNumeric(const SfzOpcodeMap &values,
                                 const char *key,
                                 double fallback)
    {
        const juce::String raw = opcodeValue(values, key).trim();
        if (raw.isEmpty())
            return fallback;

        const std::string utf8 = raw.toStdString();
        const char *start = utf8.c_str();
        char *end = nullptr;
        const double parsed = std::strtod(start, &end);
        if (end != start)
        {
            while (*end != '\0' && std::isspace((unsigned char)*end) != 0)
                ++end;
            if (*end == '\0' && std::isfinite(parsed))
                return parsed;
        }

        juce::String token = raw.trim();
        if (token.startsWith("\"") && token.endsWith("\"") && token.length() >= 2)
            token = token.substring(1, token.length() - 1).trim();
        if (token.isEmpty())
            return fallback;

        const juce::juce_wchar stepRaw = token[0];
        if (!std::isalpha((int)stepRaw))
            return fallback;
        const juce::juce_wchar step = (juce::juce_wchar)std::toupper((int)stepRaw);

        int semitone = 0;
        switch (step)
        {
        case 'C':
            semitone = 0;
            break;
        case 'D':
            semitone = 2;
            break;
        case 'E':
            semitone = 4;
            break;
        case 'F':
            semitone = 5;
            break;
        case 'G':
            semitone = 7;
            break;
        case 'A':
            semitone = 9;
            break;
        case 'B':
            semitone = 11;
            break;
        default:
            return fallback;
        }

        int index = 1;
        if (index < token.length())
        {
            const juce::juce_wchar accidental = token[index];
            if (accidental == '#')
            {
                semitone += 1;
                ++index;
            }
            else if (accidental == 'b' || accidental == 'B')
            {
                semitone -= 1;
                ++index;
            }
        }

        const juce::String octaveRaw = token.substring(index).trim();
        if (octaveRaw.isEmpty())
            return fallback;
        const std::string octaveUtf8 = octaveRaw.toStdString();
        const char *octStart = octaveUtf8.c_str();
        char *octEnd = nullptr;
        const long octave = std::strtol(octStart, &octEnd, 10);
        if (octEnd == octStart)
            return fallback;
        while (*octEnd != '\0' && std::isspace((unsigned char)*octEnd) != 0)
            ++octEnd;
        if (*octEnd != '\0')
            return fallback;

        const long midi = ((octave + 1L) * 12L) + (long)semitone;
        return (double)midi;
    }

    static juce::String resolveSfzSampleAssetPath(const juce::String &sfzAssetPath,
                                                  const juce::String &defaultPathRaw,
                                                  const juce::String &samplePathRaw)
    {
        const juce::String sfzPath = normalizeAssetPath(sfzAssetPath);
        const int slash = sfzPath.lastIndexOfChar('/');
        const juce::String sfzDir =
            slash >= 0 ? sfzPath.substring(0, slash) : juce::String();
        const juce::String defaultPath = normalizeAssetPath(defaultPathRaw);
        const juce::String samplePath = normalizeAssetPath(samplePathRaw);

        juce::String joined = sfzDir;
        if (defaultPath.isNotEmpty())
        {
            if (joined.isNotEmpty())
                joined << "/";
            joined << defaultPath;
        }
        if (samplePath.isNotEmpty())
        {
            if (joined.isNotEmpty())
                joined << "/";
            joined << samplePath;
        }

        return normalizeAssetPath(joined);
    }

    static void touchSampleLru(SampledAssetCache &cache, const std::string &key)
    {
        auto it = std::find(cache.sampleLru.begin(), cache.sampleLru.end(), key);
        if (it != cache.sampleLru.end())
            cache.sampleLru.erase(it);
        cache.sampleLru.push_back(key);
    }

    static std::shared_ptr<const DecodedSamplePcm>
    decodedSampleForAsset(const juce::String &sampleAssetPath)
    {
        const juce::String normalized = normalizeAssetPath(sampleAssetPath);
        if (normalized.isEmpty())
            return nullptr;
        const std::string cacheKey = normalized.toLowerCase().toStdString();

        auto &cache = sampledAssetCache();
        {
            const juce::ScopedLock lock(cache.lock);
            if (auto found = cache.samples.find(cacheKey); found != cache.samples.end())
            {
                touchSampleLru(cache, cacheKey);
                return found->second;
            }
        }

        const juce::File sampleFile = resolveFlutterAssetFile(normalized);
        if (!sampleFile.existsAsFile())
        {
            juce::Logger::writeToLog(
                "iOS sampled instrument missing sample file: " + normalized);
            return nullptr;
        }

        juce::AudioFormatManager formats;
        formats.registerBasicFormats();
        std::unique_ptr<juce::AudioFormatReader> reader(
            formats.createReaderFor(sampleFile));
        if (reader == nullptr || reader->lengthInSamples <= 1)
        {
            juce::Logger::writeToLog(
                "iOS sampled instrument could not decode sample file: " +
                sampleFile.getFullPathName());
            return nullptr;
        }
        if (reader->lengthInSamples > (juce::int64)std::numeric_limits<int>::max())
        {
            juce::Logger::writeToLog(
                "iOS sampled instrument sample too large to decode: " +
                sampleFile.getFullPathName());
            return nullptr;
        }

        const int frameCount = (int)reader->lengthInSamples;
        juce::AudioBuffer<float> decodedBuffer(2, frameCount);
        const bool ok = reader->read(&decodedBuffer,
                                     0,
                                     frameCount,
                                     0,
                                     true,
                                     true);
        if (!ok)
            return nullptr;

        auto decoded = std::make_shared<DecodedSamplePcm>();
        decoded->sampleRate =
            (int)juce::jlimit(4000.0, 192000.0, reader->sampleRate);
        decoded->left.assign(decodedBuffer.getReadPointer(0),
                             decodedBuffer.getReadPointer(0) + frameCount);
        if (decodedBuffer.getNumChannels() > 1)
        {
            decoded->right.assign(decodedBuffer.getReadPointer(1),
                                  decodedBuffer.getReadPointer(1) + frameCount);
        }
        else
        {
            decoded->right = decoded->left;
        }
        float peak = 0.0f;
        for (int i = 0; i < frameCount; ++i)
        {
            peak = juce::jmax(peak, std::abs(decoded->left[(size_t)i]));
            peak = juce::jmax(peak, std::abs(decoded->right[(size_t)i]));
        }
        decoded->peak = juce::jlimit(0.001f, 1.0f, peak);

        {
            const juce::ScopedLock lock(cache.lock);
            cache.samples[cacheKey] = decoded;
            touchSampleLru(cache, cacheKey);
            constexpr size_t kMaxCachedSamples = 64;
            while (cache.sampleLru.size() > kMaxCachedSamples)
            {
                const std::string oldest = cache.sampleLru.front();
                cache.sampleLru.pop_front();
                cache.samples.erase(oldest);
            }
        }

        return decoded;
    }

    static std::shared_ptr<const SampledDefinition>
    sampledDefinitionForAsset(const juce::String &sfzAssetPathRaw)
    {
        const juce::String sfzAssetPath = normalizeAssetPath(sfzAssetPathRaw);
        if (sfzAssetPath.isEmpty())
            return nullptr;

        const std::string cacheKey = sfzAssetPath.toLowerCase().toStdString();
        auto &cache = sampledAssetCache();
        {
            const juce::ScopedLock lock(cache.lock);
            if (auto found = cache.definitions.find(cacheKey);
                found != cache.definitions.end())
            {
                return found->second;
            }
        }

        const juce::File sfzFile = resolveFlutterAssetFile(sfzAssetPath);
        if (!sfzFile.existsAsFile())
        {
            juce::Logger::writeToLog(
                "iOS sampled instrument missing SFZ file: " + sfzAssetPath);
            return nullptr;
        }

        const juce::String sfzText = sfzFile.loadFileAsString();
        if (sfzText.isEmpty())
        {
            juce::Logger::writeToLog(
                "iOS sampled instrument SFZ file was empty: " +
                sfzFile.getFullPathName());
            return nullptr;
        }

        SfzOpcodeMap control;
        SfzOpcodeMap global;
        SfzOpcodeMap master;
        SfzOpcodeMap group;
        SfzOpcodeMap *region = nullptr;
        std::vector<SfzOpcodeMap> rawRegions;
        juce::String currentBlock;

        juce::StringArray lines;
        lines.addLines(sfzText);
        for (const auto &rawLine : lines)
        {
            const auto parsed = parseSfzLine(rawLine);
            if (parsed.blockTag.isEmpty() && parsed.opcodes.empty())
                continue;

            if (parsed.blockTag.isNotEmpty())
            {
                const juce::String tag = parsed.blockTag;
                currentBlock = tag;
                region = nullptr;
                if (tag == "group")
                {
                    group.clear();
                }
                else if (tag == "master")
                {
                    master.clear();
                }
                else if (tag == "region")
                {
                    rawRegions.emplace_back();
                    region = &rawRegions.back();
                    mergeOpcodeMap(*region, control);
                    mergeOpcodeMap(*region, global);
                    mergeOpcodeMap(*region, master);
                    mergeOpcodeMap(*region, group);
                }
            }

            const auto &opcodes = parsed.opcodes;
            if (opcodes.empty())
                continue;

            if (currentBlock == "control")
                mergeOpcodeMap(control, opcodes);
            else if (currentBlock == "global")
                mergeOpcodeMap(global, opcodes);
            else if (currentBlock == "master")
                mergeOpcodeMap(master, opcodes);
            else if (currentBlock == "group")
                mergeOpcodeMap(group, opcodes);
            else if (currentBlock == "region")
            {
                if (region == nullptr)
                {
                    rawRegions.emplace_back();
                    region = &rawRegions.back();
                    mergeOpcodeMap(*region, control);
                    mergeOpcodeMap(*region, global);
                    mergeOpcodeMap(*region, master);
                    mergeOpcodeMap(*region, group);
                }
                mergeOpcodeMap(*region, opcodes);
            }
        }

        const juce::String defaultPathRaw = opcodeValue(control, "default_path");
        const double globalAttackSec =
            readSfzNumeric(global, "ampeg_attack", 0.005);
        const double globalReleaseSec =
            readSfzNumeric(global, "ampeg_release", 0.35);
        const double globalVol = readSfzNumeric(global, "volume", 0.0);

        auto definition = std::make_shared<SampledDefinition>();
        definition->sfzAssetPath = sfzAssetPath;
        definition->defaultAttackSec = juce::jlimit(0.0, 4.0, globalAttackSec);
        definition->defaultReleaseSec =
            juce::jlimit(0.0, 12.0, globalReleaseSec);
        definition->regions.reserve(rawRegions.size());

        for (const auto &r : rawRegions)
        {
            const juce::String sampleRaw = opcodeValue(r, "sample").trim();
            if (sampleRaw.isEmpty())
                continue;

            const juce::String sampleAssetPath = resolveSfzSampleAssetPath(
                sfzAssetPath,
                opcodeValue(r, "default_path").isNotEmpty()
                    ? opcodeValue(r, "default_path")
                    : defaultPathRaw,
                sampleRaw);
            SampledRegion regionDef;
            regionDef.sampleAssetPath = sampleAssetPath;
            const double key = readSfzNumeric(
                r, "key", std::numeric_limits<double>::quiet_NaN());
            const double defaultLoKey = std::isfinite(key) ? key : 0.0;
            const double defaultHiKey = std::isfinite(key) ? key : 127.0;
            regionDef.loKey = juce::jlimit(
                0,
                127,
                (int)std::lround(readSfzNumeric(r, "lokey", defaultLoKey)));
            regionDef.hiKey = juce::jlimit(
                regionDef.loKey,
                127,
                (int)std::lround(readSfzNumeric(r, "hikey", defaultHiKey)));

            double keyCenter = readSfzNumeric(r, "pitch_keycenter", std::numeric_limits<double>::quiet_NaN());
            if (!std::isfinite(keyCenter))
            {
                keyCenter = std::isfinite(key)
                                ? key
                                : (double)std::lround(
                                      (regionDef.loKey + regionDef.hiKey) * 0.5);
            }
            regionDef.keyCenter =
                juce::jlimit(0, 127, (int)std::lround(keyCenter));
            regionDef.loVel =
                juce::jlimit(0, 127, (int)std::lround(readSfzNumeric(r, "lovel", 0.0)));
            regionDef.hiVel =
                juce::jlimit(0, 127, (int)std::lround(readSfzNumeric(r, "hivel", 127.0)));

            const double regionVolDb = juce::jlimit(
                -24.0,
                12.0,
                readSfzNumeric(r, "volume", globalVol));
            regionDef.gainLinear = std::pow(10.0, regionVolDb / 20.0);
            regionDef.attackSec = juce::jlimit(
                0.0,
                4.0,
                readSfzNumeric(r, "ampeg_attack", globalAttackSec));
            regionDef.releaseSec = juce::jlimit(
                0.0,
                12.0,
                readSfzNumeric(r, "ampeg_release", globalReleaseSec));
            regionDef.pitchKeytrack = juce::jlimit(
                -1200.0,
                1200.0,
                readSfzNumeric(r, "pitch_keytrack", 100.0));
            regionDef.pitchOffsetSemitones = juce::jlimit(
                -48.0,
                48.0,
                readSfzNumeric(r, "transpose", 0.0) +
                    (readSfzNumeric(r, "tune", 0.0) / 100.0));
            regionDef.sampleStartFrame = juce::jmax(
                0,
                (int)std::lround(readSfzNumeric(r, "offset", 0.0)));
            regionDef.sampleEndFrameExclusive = juce::jmax(
                0,
                (int)std::lround(readSfzNumeric(r, "end", -1.0)) + 1);
            regionDef.oneShot =
                opcodeValue(r, "loop_mode").trim().toLowerCase() == "one_shot";
            regionDef.seqLength = juce::jmax(
                1,
                (int)std::lround(readSfzNumeric(r, "seq_length", 1.0)));
            regionDef.seqPosition = juce::jlimit(
                1,
                regionDef.seqLength,
                (int)std::lround(readSfzNumeric(r, "seq_position", 1.0)));
            regionDef.loRand = juce::jlimit(
                0.0,
                1.0,
                readSfzNumeric(r, "lorand", 0.0));
            regionDef.hiRand = juce::jlimit(
                regionDef.loRand,
                1.0,
                readSfzNumeric(r, "hirand", 1.0));
            definition->regions.push_back(regionDef);
        }

        if (definition->regions.empty())
        {
            juce::Logger::writeToLog(
                "iOS sampled instrument resolved zero playable regions for: " +
                sfzAssetPath);
            return nullptr;
        }

        {
            const juce::ScopedLock lock(cache.lock);
            cache.definitions[cacheKey] = definition;
        }
        return definition;
    }

    static juce::String sfzAssetPathForInstrument(const juce::String &instrumentId,
                                                  const juce::String &instrumentName)
    {
        const juce::String id = instrumentId.toLowerCase().trim();
        if (id.startsWith("sfz_asset:"))
            return normalizeAssetPath(instrumentId.substring(10));
        if (id == "sfz.vsco.mixroom_drum_starter")
            return "assets/instruments/VSCO-2-CE-1.1.0/MixroomDrumStarter.sfz";
        if (id == "sfz.vsco.mixroom_acoustic_drum_kit")
            return "assets/instruments/VSCO-2-CE-1.1.0/MixroomAcousticDrumKit.sfz";
        if (id == "sfz.vsco.mixroom_dry_drum_kit")
            return "assets/instruments/VSCO-2-CE-1.1.0/MixroomDryDrumKit.sfz";
        if (id == "sfz.vsco.violin_ens_pizz")
            return "assets/instruments/VSCO-2-CE-1.1.0/ViolinEnsPizz.sfz";
        if (id == "sfz.vsco.trumpet_stac")
            return "assets/instruments/VSCO-2-CE-1.1.0/TrumpetStac.sfz";
        if (id == "sfz.vsco.tuba_stac")
            return "assets/instruments/VSCO-2-CE-1.1.0/TubaStac.sfz";
        if (id == "sfz.vsco.bassoon_stac")
            return "assets/instruments/VSCO-2-CE-1.1.0/BassoonStac.sfz";
        if (id == "sfz.vsco.flute_stac")
            return "assets/instruments/VSCO-2-CE-1.1.0/FluteStac.sfz";
        if (id == "sfz.vsco.clarinet_stac")
            return "assets/instruments/VSCO-2-CE-1.1.0/ClarinetStac.sfz";
        if (id == "sfz.vsco.oboe_stac")
            return "assets/instruments/VSCO-2-CE-1.1.0/OboeStac.sfz";
        if (id == "sfz.vsco.piccolo_sus")
            return "assets/instruments/VSCO-2-CE-1.1.0/PiccoloSus.sfz";
        if (id == "sfz.vsco.piccolo_stac")
            return "assets/instruments/VSCO-2-CE-1.1.0/PiccoloStac.sfz";
        if (id == "sfz.vsco.organ_quiet")
            return "assets/instruments/VSCO-2-CE-1.1.0/OrganQuiet.sfz";
        if (id == "sfz.vsco.organ_loud")
            return "assets/instruments/VSCO-2-CE-1.1.0/OrganLoud.sfz";
        if (id == "sfz.vsco.upright_piano")
            return "assets/instruments/VSCO-2-CE-1.1.0/UprightPiano.sfz";
        if (id == "sfz.vsco.marimba")
            return "assets/instruments/VSCO-2-CE-1.1.0/Marimba.sfz";
        if (id == "sfz.vsco.glockenspiel")
            return "assets/instruments/VSCO-2-CE-1.1.0/Glockenspiel.sfz";
        if (id == "sfz.vsco.tubular_bells")
            return "assets/instruments/VSCO-2-CE-1.1.0/TubularBells.sfz";
        if (id == "sfz.vsco.xylophone")
            return "assets/instruments/VSCO-2-CE-1.1.0/Xylophone.sfz";
        return {};
    }

    static std::shared_ptr<const SampledDefinition>
    resolveSampledDefinition(const juce::String &instrumentId,
                             const juce::String &instrumentName)
    {
        const juce::String assetPath =
            sfzAssetPathForInstrument(instrumentId, instrumentName);
        if (assetPath.isEmpty())
            return nullptr;
        return sampledDefinitionForAsset(assetPath);
    }

    static bool isSampledRegionReady(const SampledRegion &region) noexcept
    {
        return region.sample != nullptr && region.sample->frameCount() >= 2;
    }

    static const SampledRegion *pickSampledRegion(const SampledDefinition &definition,
                                                  int pitch,
                                                  int velocity,
                                                  int sequenceStep = 0)
    {
        auto random01For = [&](const SampledRegion &region)
        {
            uint32_t seed = 0x45d9f3bu;
            seed ^= (uint32_t)(pitch * 1009);
            seed ^= (uint32_t)(velocity * 9176);
            seed ^= (uint32_t)(sequenceStep * 6151);
            seed ^= (uint32_t)(region.keyCenter * 313);
            seed ^= (uint32_t)(region.loKey * 137);
            seed ^= (uint32_t)(region.hiKey * 271);
            seed ^= seed >> 16;
            seed &= 0x7fffffffu;
            return (double)seed / (double)0x7fffffffu;
        };

        auto pickBest =
            [&](bool enforceVelocity, bool enforceSequence) -> const SampledRegion *
        {
            const SampledRegion *best = nullptr;
            int bestKeyDistance = std::numeric_limits<int>::max();
            int bestVelDistance = std::numeric_limits<int>::max();

            for (const auto &region : definition.regions)
            {
                if (pitch < region.loKey || pitch > region.hiKey)
                    continue;
                if (enforceVelocity &&
                    (velocity < region.loVel || velocity > region.hiVel))
                    continue;
                if (enforceSequence && region.seqLength > 1)
                {
                    const int expected = (sequenceStep % region.seqLength) + 1;
                    if (region.seqPosition != expected)
                        continue;
                }
                const double randomValue = random01For(region);
                if (randomValue < region.loRand || randomValue >= region.hiRand)
                    continue;

                const int keyDistance = std::abs(pitch - region.keyCenter);
                const int velDistance =
                    velocity < region.loVel ? (region.loVel - velocity)
                                            : velocity > region.hiVel ? (velocity - region.hiVel)
                                                                      : 0;
                if (best == nullptr || keyDistance < bestKeyDistance ||
                    (keyDistance == bestKeyDistance &&
                     velDistance < bestVelDistance))
                {
                    best = &region;
                    bestKeyDistance = keyDistance;
                    bestVelDistance = velDistance;
                }
            }
            return best;
        };

        if (auto *best = pickBest(true, true))
            return best;
        if (auto *best = pickBest(false, true))
            return best;
        if (auto *best = pickBest(true, false))
            return best;
        return pickBest(false, false);
    }

    static std::unordered_set<size_t> sampledRegionIndicesForNotes(
        const SampledDefinition &definition,
        const juce::Array<TimelineMidiNote> &notes,
        bool usesDrumKitPitchMap)
    {
        std::unordered_set<size_t> regionIndices;
        regionIndices.reserve((size_t)juce::jmax(1, notes.size()));

        for (int i = 0; i < notes.size(); ++i)
        {
            const auto &note = notes.getReference(i);
            const int sampledPitch =
                sampledMidiPitchForDrumMap(usesDrumKitPitchMap, note.pitch);
            const int midiVelocity = juce::jlimit(
                0,
                127,
                (int)std::lround(
                    juce::jlimit(0.0, 1.0, note.velocity) * 127.0));
            if (const auto *region = pickSampledRegion(
                    definition,
                    sampledPitch,
                    midiVelocity,
                    i))
            {
                regionIndices.insert(
                    (size_t)(region - definition.regions.data()));
            }
        }

        return regionIndices;
    }

    static void preloadSampledRegionsForNotes(
        const SampledDefinition &definition,
        const juce::Array<TimelineMidiNote> &notes,
        bool usesDrumKitPitchMap)
    {
        const auto regionIndices = sampledRegionIndicesForNotes(
            definition, notes, usesDrumKitPitchMap);

        for (const auto index : regionIndices)
        {
            if (index >= definition.regions.size())
                continue;
            const auto &region = definition.regions[index];
            if (region.sampleAssetPath.trim().isNotEmpty())
                juce::ignoreUnused(
                    decodedSampleForAsset(region.sampleAssetPath));
        }
    }

    static std::shared_ptr<const SampledDefinition>
    prepareSampledDefinitionForNotes(
        const std::shared_ptr<const SampledDefinition> &metadata,
        const juce::Array<TimelineMidiNote> &notes,
        bool usesDrumKitPitchMap)
    {
        if (metadata == nullptr)
            return nullptr;

        auto prepared = std::make_shared<SampledDefinition>(*metadata);
        const auto regionIndices = sampledRegionIndicesForNotes(
            *metadata, notes, usesDrumKitPitchMap);

        for (const auto index : regionIndices)
        {
            if (index >= prepared->regions.size())
                continue;
            auto &region = prepared->regions[index];
            if (region.sampleAssetPath.trim().isEmpty())
                continue;
            auto sample = decodedSampleForAsset(region.sampleAssetPath);
            if (sample != nullptr && sample->frameCount() >= 2)
                region.sample = std::move(sample);
        }

        std::shared_ptr<const SampledDefinition> immutable =
            std::move(prepared);
        return immutable;
    }

    static int sampledRegionFrameLimit(const SampledRegion &region,
                                       const DecodedSamplePcm &pcm)
    {
        const int requestedEnd =
            region.sampleEndFrameExclusive > 0
                ? region.sampleEndFrameExclusive
                : pcm.frameCount();
        return juce::jlimit(
            juce::jmin(region.sampleStartFrame + 1, pcm.frameCount()),
            pcm.frameCount(),
            requestedEnd);
    }

    static double sampledPlaybackRate(const DecodedSamplePcm &pcm,
                                      const SampledRegion &region,
                                      double notePitch,
                                      double outputSampleRate)
    {
        const double semitoneOffset =
            ((notePitch - (double)region.keyCenter) *
             (region.pitchKeytrack / 100.0)) +
            region.pitchOffsetSemitones;
        return std::pow(2.0, semitoneOffset / 12.0) *
               ((double)pcm.sampleRate / outputSampleRate);
    }

    static SampledRegion samplerRegionForPreset(
        const SampledRegion &source,
        const InstrumentPreset &preset,
        int midiPitch)
    {
        SampledRegion region = source;
        if (region.sample == nullptr)
            return region;

        const int frameCount = region.sample->frameCount();
        if (frameCount < 2)
            return region;

        const int baseStart =
            juce::jlimit(0, frameCount - 1, source.sampleStartFrame);
        const int baseEnd = sampledRegionFrameLimit(source, *region.sample);
        const int baseFrames = juce::jmax(2, baseEnd - baseStart);
        const double startNorm = juce::jlimit(0.0, 0.98, preset.sampleStartNorm);
        const double endNorm =
            juce::jlimit(startNorm + 0.02, 1.0, preset.sampleEndNorm);

        int startFrame = baseStart + (int)std::round(startNorm * (double)(baseFrames - 1));
        int endFrame = baseStart + (int)std::round(endNorm * (double)baseFrames);
        endFrame = juce::jlimit(startFrame + 1, baseEnd, endFrame);

        if (preset.sliceMode >= 0.5)
        {
            const int slices = juce::jlimit(2, 32, (int)std::round(preset.sliceCount));
            const int root = juce::jlimit(0, 127, (int)std::round(preset.rootNote));
            const int sliceIndex = juce::jlimit(0, slices - 1, midiPitch - root);
            const int trimFrames = juce::jmax(2, endFrame - startFrame);
            const int sliceStart = startFrame + (int)std::floor((double)trimFrames * (double)sliceIndex / (double)slices);
            const int sliceEnd = startFrame + (int)std::floor((double)trimFrames * (double)(sliceIndex + 1) / (double)slices);
            startFrame = juce::jlimit(startFrame, endFrame - 1, sliceStart);
            endFrame = juce::jlimit(startFrame + 1, endFrame, sliceEnd);
        }

        region.sampleStartFrame = startFrame;
        region.sampleEndFrameExclusive = endFrame;
        region.keyCenter = mixroom::effectiveSampleKeyCenter(
            source.keyCenter, preset.rootNote);
        if (preset.timeStretchMode >= 0.5)
            region.pitchKeytrack = 0.0;
        region.oneShot = preset.samplePlayMode >= 0.5;
        return region;
    }

    static double sampledPlayableDurationSec(const SampledRegion &region,
                                             double notePitch,
                                             double outputSampleRate)
    {
        if (region.sample == nullptr || outputSampleRate <= 0.0)
            return 0.0;
        const auto &pcm = *region.sample;
        const int frameCount = pcm.frameCount();
        if (frameCount < 2)
            return 0.0;
        const int startFrame = juce::jlimit(0, frameCount - 1, region.sampleStartFrame);
        const int endFrame = sampledRegionFrameLimit(region, pcm);
        const int usableFrames = endFrame - startFrame;
        if (usableFrames < 2)
            return 0.0;
        const double playbackRate =
            sampledPlaybackRate(pcm, region, notePitch, outputSampleRate);
        if (!std::isfinite(playbackRate) || playbackRate <= 0.0)
            return 0.0;
        return juce::jmax(0.0, ((double)(usableFrames - 1)) /
                                   (outputSampleRate * playbackRate));
    }

    static bool renderSampledStereo(
        const std::shared_ptr<const DecodedSamplePcm> &sample,
        const SampledRegion &region,
        const InstrumentPreset &preset,
        double notePitch,
        double ageSec,
        double outputSampleRate,
        float &outL,
        float &outR)
    {
        outL = 0.0f;
        outR = 0.0f;
        if (sample == nullptr || outputSampleRate <= 0.0 || ageSec < 0.0)
            return false;

        const auto &pcm = *sample;
        const int frameCount = pcm.frameCount();
        if (frameCount < 2)
            return false;

        const int startFrame =
            juce::jlimit(0, frameCount - 1, region.sampleStartFrame);
        const int endFrame = sampledRegionFrameLimit(region, pcm);
        const int usableFrames = endFrame - startFrame;
        if (usableFrames < 2)
            return false;

        const double playbackRate =
            sampledPlaybackRate(pcm, region, notePitch, outputSampleRate);
        if (!std::isfinite(playbackRate) || playbackRate <= 0.0)
            return false;

        const double samplePos =
            (double)startFrame + (ageSec * outputSampleRate * playbackRate);
        if (samplePos < (double)startFrame ||
            samplePos >= (double)(endFrame - 1))
            return false;

        double readPos = samplePos;
        if (preset.reverseSample >= 0.5)
            readPos = (double)(endFrame - 1) - (samplePos - (double)startFrame);

        const int index = juce::jlimit(startFrame, endFrame - 1, (int)std::floor(readPos));
        const int nextIndex =
            preset.reverseSample >= 0.5
                ? juce::jmax(index - 1, startFrame)
                : juce::jmin(index + 1, endFrame - 1);
        const double frac = readPos - (double)index;

        const float l0 = pcm.left[(size_t)index];
        const float l1 = pcm.left[(size_t)nextIndex];
        const float r0 = pcm.right[(size_t)index];
        const float r1 = pcm.right[(size_t)nextIndex];
        float l = (float)(l0 + (l1 - l0) * frac);
        float r = (float)(r0 + (r1 - r0) * frac);

        if (preset.sampleFilterCutoffHz < 19500.0)
        {
            const int prevIndex = juce::jmax(index - 1, startFrame);
            const int nextSmoothIndex = juce::jmin(index + 1, endFrame - 1);
            const float alpha = (float)juce::jlimit(
                0.0,
                1.0,
                preset.sampleFilterCutoffHz / 20000.0);
            const float smoothL =
                (pcm.left[(size_t)prevIndex] + l + pcm.left[(size_t)nextSmoothIndex]) / 3.0f;
            const float smoothR =
                (pcm.right[(size_t)prevIndex] + r + pcm.right[(size_t)nextSmoothIndex]) / 3.0f;
            l = smoothL + ((l - smoothL) * alpha);
            r = smoothR + ((r - smoothR) * alpha);
        }

        if (preset.normalizeSample >= 0.5)
        {
            const float normGain = 1.0f / juce::jlimit(0.001f, 1.0f, pcm.peak);
            l *= normGain;
            r *= normGain;
        }

        outL = juce::jlimit(-1.0f, 1.0f, l);
        outR = juce::jlimit(-1.0f, 1.0f, r);
        return true;
    }

    static bool renderSampledStereo(const SampledRegion &region,
                                    const InstrumentPreset &preset,
                                    double notePitch,
                                    double ageSec,
                                    double outputSampleRate,
                                    float &outL,
                                    float &outR)
    {
        return renderSampledStereo(
            region.sample,
            region,
            preset,
            notePitch,
            ageSec,
            outputSampleRate,
            outL,
            outR);
    }

    static bool renderGranularStereo(const SampledRegion &region,
                                     const InstrumentPreset &preset,
                                     double notePitch,
                                     double noteAgeSec,
                                     double outputSampleRate,
                                     int grainSeed,
                                     float &outL,
                                     float &outR)
    {
        outL = 0.0f;
        outR = 0.0f;
        if (region.sample == nullptr || outputSampleRate <= 0.0 || noteAgeSec < 0.0)
            return false;

        const auto &pcm = *region.sample;
        const int frameCount = pcm.frameCount();
        if (frameCount < 4)
            return false;

        const int startFrame = juce::jlimit(0, frameCount - 1, region.sampleStartFrame);
        const int endFrame = sampledRegionFrameLimit(region, pcm);
        const int trimFrames = endFrame - startFrame;
        if (trimFrames < 4)
            return false;

        const double grainHoldSec = juce::jlimit(0.002, 0.5, preset.grainHoldMs / 1000.0);
        const double grainAttackSec = juce::jlimit(0.0, grainHoldSec * 0.5, preset.grainAttackMs / 1000.0);
        const double grainSpacingSec = juce::jmax(
            1.0 / outputSampleRate,
            grainHoldSec * juce::jlimit(1.0, 400.0, preset.grainSpacingPct) / 100.0);
        const int grainIndex = (int)std::floor(noteAgeSec / grainSpacingSec);
        const double grainStartSec = (double)grainIndex * grainSpacingSec;
        const double grainAgeSec = noteAgeSec - grainStartSec;
        if (grainAgeSec < 0.0 || grainAgeSec >= grainHoldSec)
            return true;

        double grainEnv = 1.0;
        if (grainAttackSec > 0.0)
        {
            const double fadeIn = juce::jlimit(0.0, 1.0, grainAgeSec / grainAttackSec);
            const double fadeOut = juce::jlimit(0.0, 1.0, (grainHoldSec - grainAgeSec) / grainAttackSec);
            grainEnv = std::sin(juce::MathConstants<double>::halfPi * juce::jmin(fadeIn, fadeOut));
        }

        const int keyMode = juce::jlimit(0, 3, (int)std::round(preset.grainKeyMode));
        const double playbackRate =
            keyMode == 0
                ? std::pow(2.0, (notePitch - preset.rootNote) / 12.0) *
                      ((double)pcm.sampleRate / outputSampleRate)
                : ((double)pcm.sampleRate / outputSampleRate);
        if (!std::isfinite(playbackRate) || playbackRate <= 0.0)
            return false;

        double keyOffsetFrames = 0.0;
        if (keyMode == 1)
        {
            keyOffsetFrames =
                juce::jlimit(0.0, 1.0, (notePitch - preset.rootNote) / 24.0) *
                (double)trimFrames;
        }
        else if (keyMode >= 2)
        {
            const int steps = juce::jmax(1, (int)std::round(preset.sliceCount) - 1);
            keyOffsetFrames =
                juce::jlimit(0.0, (double)steps, notePitch - preset.rootNote) /
                (double)steps * (double)trimFrames;
        }

        const double randomSigned = hashNoise(grainSeed + grainIndex * 1973);
        const double randomFrames =
            randomSigned * (double)trimFrames *
            (juce::jlimit(0.0, 100.0, preset.grainRandomPct) / 100.0) * 0.18;
        const double lfoFrames =
            (double)trimFrames *
            (juce::jlimit(0.0, 100.0, preset.grainLfoDepthPct) / 100.0) *
            0.5 *
            std::sin(juce::MathConstants<double>::twoPi *
                     juce::jlimit(0.0, 20.0, preset.grainLfoSpeedHz) *
                     noteAgeSec);
        const double transientFrames =
            preset.grainTransientMode >= 0.5
                ? (preset.grainTransientHoldMs / 1000.0) * (double)pcm.sampleRate
                : 0.0;
        const double waveAdvanceFrames =
            preset.grainPositionHold >= 0.5
                ? 0.0
                : (double)grainIndex * grainHoldSec * outputSampleRate *
                      juce::jlimit(-400.0, 400.0, preset.waveSpacingPct) / 100.0;
        double sourcePos =
            (double)startFrame + keyOffsetFrames + transientFrames + waveAdvanceFrames +
            randomFrames + lfoFrames + grainAgeSec * outputSampleRate * playbackRate;

        if (preset.grainLoop >= 0.5)
        {
            sourcePos = (double)startFrame + std::fmod(sourcePos - (double)startFrame, (double)trimFrames);
            if (sourcePos < (double)startFrame)
                sourcePos += (double)trimFrames;
        }
        else if (sourcePos < (double)startFrame || sourcePos >= (double)(endFrame - 1))
        {
            return false;
        }

        double readPos = sourcePos;
        if (preset.reverseSample >= 0.5)
            readPos = (double)(endFrame - 1) - (sourcePos - (double)startFrame);

        const int index = juce::jlimit(startFrame, endFrame - 1, (int)std::floor(readPos));
        const int nextIndex =
            preset.reverseSample >= 0.5
                ? juce::jmax(index - 1, startFrame)
                : juce::jmin(index + 1, endFrame - 1);
        const double frac = juce::jlimit(0.0, 1.0, readPos - (double)index);
        float l = (float)(pcm.left[(size_t)index] +
                          (pcm.left[(size_t)nextIndex] - pcm.left[(size_t)index]) * frac);
        float r = (float)(pcm.right[(size_t)index] +
                          (pcm.right[(size_t)nextIndex] - pcm.right[(size_t)index]) * frac);

        if (preset.sampleFilterCutoffHz < 19500.0)
        {
            const int prevIndex = juce::jmax(index - 1, startFrame);
            const int nextSmoothIndex = juce::jmin(index + 1, endFrame - 1);
            const float alpha = (float)juce::jlimit(0.0, 1.0, preset.sampleFilterCutoffHz / 20000.0);
            const float smoothL =
                (pcm.left[(size_t)prevIndex] + l + pcm.left[(size_t)nextSmoothIndex]) / 3.0f;
            const float smoothR =
                (pcm.right[(size_t)prevIndex] + r + pcm.right[(size_t)nextSmoothIndex]) / 3.0f;
            l = smoothL + ((l - smoothL) * alpha);
            r = smoothR + ((r - smoothR) * alpha);
        }

        if (preset.normalizeSample >= 0.5)
        {
            const float normGain = 1.0f / juce::jlimit(0.001f, 1.0f, pcm.peak);
            l *= normGain;
            r *= normGain;
        }

        const double pan = juce::jlimit(
            -0.95,
            0.95,
            preset.grainPan * ((grainIndex & 1) == 0 ? -1.0 : 1.0));
        const float leftGain = (float)std::sqrt(0.5 * (1.0 - pan));
        const float rightGain = (float)std::sqrt(0.5 * (1.0 + pan));
        outL = juce::jlimit(-1.0f, 1.0f, l * (float)grainEnv * leftGain);
        outR = juce::jlimit(-1.0f, 1.0f, r * (float)grainEnv * rightGain);
        return true;
    }

    static const std::unordered_map<std::string, InstrumentPreset> &presetMap()
    {
        static const std::unordered_map<std::string, InstrumentPreset> map = {
            {"mixroom.basic_synth", {InstrumentFamily::basic, 1, 3200.0, 18.0, 180.0, 0.08, 0.36, 0.002, 0.12, 0.56, 0.08, 0.0, 0.02}},
            {"mixroom.bass_mono", {InstrumentFamily::bass, 2, 760.0, 4.0, 260.0, 0.03, 0.31, 0.0, 0.0, 0.32, 0.02, 1.25, 0.0}},
            {"mixroom.soft_pad", {InstrumentFamily::pad, 3, 2100.0, 80.0, 620.0, 0.02, 0.31, 0.012, 0.28, 0.47, 0.04, 0.0, 0.03}},
            {"mixroom.figbug_wavetable", {InstrumentFamily::wavetable, 1, 5200.0, 6.0, 240.0, 0.18, 0.33, 0.006, 0.16, 0.72, 0.14, 0.0, 0.03}},
            {"mixroom.sarah_harmonic", {InstrumentFamily::pad, 3, 1980.0, 72.0, 760.0, 0.03, 0.30, 0.0, 0.10, 0.34, 0.02, 0.0, 0.02, 0.0}},
            {"mixroom.vanilla_poly", {InstrumentFamily::keys, 0, 3680.0, 5.0, 220.0, 0.03, 0.36, 0.001, 0.03, 0.58, 0.26, 0.0, 0.01}},
            {"mixroom.duck_synth", {InstrumentFamily::bass, 2, 1780.0, 2.0, 130.0, 0.28, 0.35, 0.003, 0.02, 0.78, 0.24, 9.0, 0.05}},
            {"mixroom.chow_kick", {InstrumentFamily::drum, 0, 900.0, 0.0, 90.0, 0.42, 0.42, 0.0, 0.0, 0.52, 0.40, 16.0, 0.14}},
            {"mixroom.warm_keys", {InstrumentFamily::keys, 1, 1880.0, 20.0, 480.0, 0.06, 0.34, 0.004, 0.07, 0.18, 0.08, 0.0, 0.02}},
            {"mixroom.super_saw", {InstrumentFamily::lead, 1, 6200.0, 4.0, 180.0, 0.22, 0.34, 0.01, 0.20, 0.75, 0.11, 0.0, 0.03}},
            {"mixroom.gentle_pluck", {InstrumentFamily::pluck, 3, 4800.0, 2.0, 130.0, 0.08, 0.33, 0.004, 0.11, 0.68, 0.24, 0.0, 0.03}},
            {"mixroom.sub_bass", {InstrumentFamily::bass, 2, 560.0, 3.0, 300.0, 0.015, 0.33, 0.0, 0.0, 0.18, 0.01, 0.85, 0.0}},
            {"mixroom.analog_brass", {InstrumentFamily::brass, 2, 2140.0, 32.0, 340.0, 0.18, 0.35, 0.007, 0.06, 0.34, 0.12, 0.0, 0.06}},
            {"mixroom.drum_acoustic_easy", {InstrumentFamily::drum, 1, 2300.0, 0.0, 120.0, 0.18, 0.41, 0.0, 0.0, 0.52, 0.26, 10.0, 0.15}},
            {"mixroom.drum_808_starter", {InstrumentFamily::drum, 0, 1100.0, 0.0, 190.0, 0.36, 0.44, 0.0, 0.0, 0.60, 0.35, 24.0, 0.18}},
            {"mixroom.drum_lofi", {InstrumentFamily::drum, 3, 1700.0, 1.0, 150.0, 0.28, 0.41, 0.0, 0.0, 0.45, 0.20, 12.0, 0.20}},
            {"mixroom.drum_house", {InstrumentFamily::drum, 1, 2600.0, 0.0, 95.0, 0.24, 0.42, 0.0, 0.0, 0.58, 0.28, 14.0, 0.17}},
            {"mixroom.night_bell", {InstrumentFamily::harmonic, 0, 5600.0, 1.0, 540.0, 0.06, 0.30, 0.002, 0.22, 0.76, 0.16, 0.0, 0.01}},
            {"mixroom.fm_keys", {InstrumentFamily::harmonic, 0, 4700.0, 3.0, 320.0, 0.05, 0.31, 0.002, 0.10, 0.78, 0.18, 0.0, 0.01}},
            {"mixroom.vintage_strings", {InstrumentFamily::pad, 1, 2400.0, 32.0, 640.0, 0.08, 0.31, 0.015, 0.24, 0.50, 0.07, 0.0, 0.02}},
            {"mixroom.neo_brass", {InstrumentFamily::brass, 0, 4320.0, 8.0, 210.0, 0.22, 0.36, 0.014, 0.18, 0.84, 0.18, 0.0, 0.03}},
            {"mixroom.reese_bass", {InstrumentFamily::bass, 1, 1300.0, 4.0, 200.0, 0.26, 0.35, 0.015, 0.08, 0.57, 0.16, 5.0, 0.05}},
            {"mixroom.air_pluck", {InstrumentFamily::pluck, 3, 5200.0, 1.0, 210.0, 0.08, 0.33, 0.008, 0.14, 0.72, 0.20, 0.0, 0.05}},
            {"mixroom.cinematic_pad", {InstrumentFamily::pad, 3, 1900.0, 95.0, 760.0, 0.05, 0.30, 0.018, 0.30, 0.44, 0.05, 0.0, 0.03}},
            {"mixroom.velvet_ep", {InstrumentFamily::keys, 3, 5400.0, 3.0, 520.0, 0.12, 0.36, 0.022, 0.22, 0.88, 0.32, 0.0, 0.03}},
            {"mixroom.house_organ", {InstrumentFamily::keys, 2, 3400.0, 0.0, 210.0, 0.11, 0.33, 0.003, 0.10, 0.62, 0.12, 0.0, 0.02}},
            {"mixroom.glass_pluck", {InstrumentFamily::pluck, 3, 5600.0, 1.0, 170.0, 0.09, 0.33, 0.007, 0.14, 0.74, 0.24, 0.0, 0.03}},
            {"mixroom.neon_lead", {InstrumentFamily::lead, 1, 6400.0, 3.0, 210.0, 0.24, 0.34, 0.012, 0.18, 0.78, 0.13, 0.0, 0.03}},
            {"mixroom.mellow_sub", {InstrumentFamily::bass, 2, 420.0, 6.0, 420.0, 0.008, 0.32, 0.0, 0.0, 0.10, 0.0, 0.35, 0.0}},
            {"mixroom.wide_air_pad", {InstrumentFamily::pad, 3, 2300.0, 74.0, 700.0, 0.04, 0.30, 0.020, 0.30, 0.50, 0.05, 0.0, 0.02}},
            {"mixroom.horn_stack", {InstrumentFamily::brass, 1, 2900.0, 20.0, 280.0, 0.16, 0.33, 0.004, 0.12, 0.58, 0.09, 0.0, 0.02}},
            {"mixroom.drum_trap", {InstrumentFamily::drum, 0, 2100.0, 0.0, 110.0, 0.32, 0.42, 0.0, 0.0, 0.62, 0.32, 18.0, 0.20}},
            {"mixroom.drum_breakbeat", {InstrumentFamily::drum, 2, 2400.0, 0.0, 130.0, 0.26, 0.42, 0.0, 0.0, 0.55, 0.25, 12.0, 0.18}},
            {"mixroom.drum_dnb", {InstrumentFamily::drum, 2, 2600.0, 0.0, 105.0, 0.33, 0.43, 0.0, 0.0, 0.67, 0.34, 20.0, 0.22}},
        };
        return map;
    }

    static InstrumentPreset resolvePreset(const juce::String &instrumentId, const juce::String &instrumentName)
    {
        const juce::String id = instrumentId.toLowerCase().trim();
        const std::string idKey = id.toStdString();
        if (auto found = presetMap().find(idKey); found != presetMap().end())
            return found->second;

        const juce::String text = (id + " " + instrumentName.toLowerCase());
        auto contains = [&](const char *needle) { return text.contains(needle); };

        if (contains("drum") || contains("kick") || contains("808"))
            return {InstrumentFamily::drum, 0, 2000.0, 0.0, 120.0, 0.3, 0.42, 0.0, 0.0, 0.58, 0.30, 16.0, 0.20};
        if (contains("bass"))
            return {InstrumentFamily::bass, 2, 1200.0, 6.0, 220.0, 0.24, 0.34, 0.004, 0.06, 0.52, 0.16, 6.0, 0.04};
        if (contains("pad") || contains("string"))
            return {InstrumentFamily::pad, 3, 2200.0, 80.0, 620.0, 0.05, 0.30, 0.012, 0.24, 0.48, 0.06, 0.0, 0.03};
        if (contains("pluck") || contains("bell"))
            return {InstrumentFamily::pluck, 3, 5100.0, 2.0, 190.0, 0.08, 0.33, 0.005, 0.13, 0.74, 0.20, 0.0, 0.03};
        if (contains("brass") || contains("horn"))
            return {InstrumentFamily::brass, 1, 2800.0, 18.0, 290.0, 0.14, 0.33, 0.004, 0.13, 0.56, 0.08, 0.0, 0.02};
        if (contains("key") || contains("piano") || contains("organ"))
            return {InstrumentFamily::keys, 0, 3300.0, 10.0, 280.0, 0.06, 0.32, 0.004, 0.12, 0.58, 0.12, 0.0, 0.02};
        if (contains("wave"))
            return {InstrumentFamily::wavetable, 1, 4800.0, 6.0, 240.0, 0.16, 0.33, 0.006, 0.14, 0.68, 0.12, 0.0, 0.03};
        if (contains("harmonic") || contains("fm"))
            return {InstrumentFamily::harmonic, 0, 3400.0, 12.0, 360.0, 0.09, 0.32, 0.005, 0.15, 0.62, 0.12, 0.0, 0.02};
        if (contains("lead") || contains("saw"))
            return {InstrumentFamily::lead, 1, 5600.0, 4.0, 200.0, 0.18, 0.34, 0.008, 0.16, 0.74, 0.10, 0.0, 0.03};

        return {InstrumentFamily::basic, 1, 3200.0, 18.0, 180.0, 0.08, 0.36, 0.002, 0.12, 0.56, 0.08, 0.0, 0.02};
    }

    static void applyParamOverrides(InstrumentPreset &preset, const juce::NamedValueSet &params)
    {
        if (params.contains(juce::Identifier("oscillator")))
            preset.oscillator = juce::jlimit(0, 3, (int)std::lround(readParam(params, "oscillator", preset.oscillator)));
        if (params.contains(juce::Identifier("cutoffHz")))
            preset.cutoffHz = juce::jlimit(200.0, 16000.0, readParam(params, "cutoffHz", preset.cutoffHz));
        if (params.contains(juce::Identifier("attackMs")))
            preset.attackMs = juce::jlimit(0.0, 1000.0, readParam(params, "attackMs", preset.attackMs));
        if (params.contains(juce::Identifier("decayMs")))
            preset.decayMs = juce::jlimit(0.0, 2000.0, readParam(params, "decayMs", preset.decayMs));
        if (params.contains(juce::Identifier("sustainLevel")))
            preset.sustainLevel = juce::jlimit(0.0, 1.0, readParam(params, "sustainLevel", preset.sustainLevel));
        if (params.contains(juce::Identifier("releaseMs")))
            preset.releaseMs = juce::jlimit(0.0, 2400.0, readParam(params, "releaseMs", preset.releaseMs));
        if (params.contains(juce::Identifier("sampleStartNorm")))
            preset.sampleStartNorm = juce::jlimit(0.0, 0.98, readParam(params, "sampleStartNorm", preset.sampleStartNorm));
        if (params.contains(juce::Identifier("sampleEndNorm")))
            preset.sampleEndNorm = juce::jlimit(0.02, 1.0, readParam(params, "sampleEndNorm", preset.sampleEndNorm));
        if (params.contains(juce::Identifier("reverseSample")))
            preset.reverseSample = juce::jlimit(0.0, 1.0, readParam(params, "reverseSample", preset.reverseSample));
        if (params.contains(juce::Identifier("normalizeSample")))
            preset.normalizeSample = juce::jlimit(0.0, 1.0, readParam(params, "normalizeSample", preset.normalizeSample));
        if (params.contains(juce::Identifier("samplePlayMode")))
            preset.samplePlayMode = juce::jlimit(0.0, 1.0, readParam(params, "samplePlayMode", preset.samplePlayMode));
        if (params.contains(juce::Identifier("rootNote")))
            preset.rootNote = juce::jlimit(0.0, 127.0, readParam(params, "rootNote", preset.rootNote));
        if (params.contains(juce::Identifier("sampleLowKey")))
            preset.sampleLowKey = juce::jlimit(0.0, 127.0, readParam(params, "sampleLowKey", preset.sampleLowKey));
        if (params.contains(juce::Identifier("sampleHighKey")))
            preset.sampleHighKey = juce::jlimit(0.0, 127.0, readParam(params, "sampleHighKey", preset.sampleHighKey));
        if (params.contains(juce::Identifier("sliceMode")))
            preset.sliceMode = juce::jlimit(0.0, 1.0, readParam(params, "sliceMode", preset.sliceMode));
        if (params.contains(juce::Identifier("sliceCount")))
            preset.sliceCount = juce::jlimit(2.0, 32.0, readParam(params, "sliceCount", preset.sliceCount));
        if (params.contains(juce::Identifier("timeStretchMode")))
            preset.timeStretchMode = juce::jlimit(0.0, 1.0, readParam(params, "timeStretchMode", preset.timeStretchMode));
        if (params.contains(juce::Identifier("sampleFilterCutoffHz")))
            preset.sampleFilterCutoffHz = juce::jlimit(80.0, 20000.0, readParam(params, "sampleFilterCutoffHz", preset.sampleFilterCutoffHz));
        if (params.contains(juce::Identifier("granularMode")))
            preset.granularMode = juce::jlimit(0.0, 1.0, readParam(params, "granularMode", preset.granularMode));
        if (params.contains(juce::Identifier("grainAttackMs")))
            preset.grainAttackMs = juce::jlimit(0.0, 250.0, readParam(params, "grainAttackMs", preset.grainAttackMs));
        if (params.contains(juce::Identifier("grainHoldMs")))
            preset.grainHoldMs = juce::jlimit(2.0, 500.0, readParam(params, "grainHoldMs", preset.grainHoldMs));
        if (params.contains(juce::Identifier("grainSpacingPct")))
            preset.grainSpacingPct = juce::jlimit(1.0, 400.0, readParam(params, "grainSpacingPct", preset.grainSpacingPct));
        if (params.contains(juce::Identifier("waveSpacingPct")))
            preset.waveSpacingPct = juce::jlimit(-400.0, 400.0, readParam(params, "waveSpacingPct", preset.waveSpacingPct));
        if (params.contains(juce::Identifier("grainPan")))
            preset.grainPan = juce::jlimit(-1.0, 1.0, readParam(params, "grainPan", preset.grainPan));
        if (params.contains(juce::Identifier("grainLfoDepthPct")))
            preset.grainLfoDepthPct = juce::jlimit(0.0, 100.0, readParam(params, "grainLfoDepthPct", preset.grainLfoDepthPct));
        if (params.contains(juce::Identifier("grainLfoSpeedHz")))
            preset.grainLfoSpeedHz = juce::jlimit(0.0, 20.0, readParam(params, "grainLfoSpeedHz", preset.grainLfoSpeedHz));
        if (params.contains(juce::Identifier("grainRandomPct")))
            preset.grainRandomPct = juce::jlimit(0.0, 100.0, readParam(params, "grainRandomPct", preset.grainRandomPct));
        if (params.contains(juce::Identifier("grainTransientMode")))
            preset.grainTransientMode = juce::jlimit(0.0, 2.0, readParam(params, "grainTransientMode", preset.grainTransientMode));
        if (params.contains(juce::Identifier("grainTransientHoldMs")))
            preset.grainTransientHoldMs = juce::jlimit(2.0, 500.0, readParam(params, "grainTransientHoldMs", preset.grainTransientHoldMs));
        if (params.contains(juce::Identifier("grainLoop")))
            preset.grainLoop = juce::jlimit(0.0, 1.0, readParam(params, "grainLoop", preset.grainLoop));
        if (params.contains(juce::Identifier("grainPositionHold")))
            preset.grainPositionHold = juce::jlimit(0.0, 1.0, readParam(params, "grainPositionHold", preset.grainPositionHold));
        if (params.contains(juce::Identifier("grainKeyMode")))
            preset.grainKeyMode = juce::jlimit(0.0, 3.0, readParam(params, "grainKeyMode", preset.grainKeyMode));
        if (params.contains(juce::Identifier("drive")))
            preset.drive = juce::jlimit(0.0, 1.0, readParam(params, "drive", preset.drive));
        if (params.contains(juce::Identifier("outputGain")))
        {
            const double maxGain = (preset.family == InstrumentFamily::sampled) ? 2.0 : 0.75;
            preset.outputGain = juce::jlimit(0.15, maxGain, readParam(params, "outputGain", preset.outputGain));
        }
        if (params.contains(juce::Identifier("detune")))
            preset.detune = juce::jlimit(0.0, 0.03, readParam(params, "detune", preset.detune));
        if (params.contains(juce::Identifier("stereoWidth")))
            preset.stereoWidth = juce::jlimit(0.0, 0.45, readParam(params, "stereoWidth", preset.stereoWidth));
        if (params.contains(juce::Identifier("tone")))
            preset.tone = juce::jlimit(0.0, 1.0, readParam(params, "tone", preset.tone));
        if (params.contains(juce::Identifier("transient")))
            preset.transient = juce::jlimit(0.0, 1.0, readParam(params, "transient", preset.transient));
        if (params.contains(juce::Identifier("noise")))
            preset.noise = juce::jlimit(0.0, 0.45, readParam(params, "noise", preset.noise));
        if (params.contains(juce::Identifier("padDetuneOffset")))
            preset.padDetuneOffset = juce::jlimit(0.0, 0.03, readParam(params, "padDetuneOffset", preset.padDetuneOffset));
        if (params.contains(juce::Identifier("pitchDropSemitones")))
            preset.pitchDropSemitones = juce::jlimit(0.0, 36.0, readParam(params, "pitchDropSemitones", preset.pitchDropSemitones));
    }

    static float renderInstrumentSample(const InstrumentPreset &preset,
                                        int pitch,
                                        double frequencyHz,
                                        double ageSec,
                                        double noteProgress,
                                        double envelope,
                                        double sampleRate,
                                        int noiseSeed)
    {
        juce::ignoreUnused(envelope);

        const double phaseA = wrapPhase(ageSec * frequencyHz);
        const double phaseB = wrapPhase(ageSec * frequencyHz * (1.0 + juce::jlimit(0.0, 0.03, preset.detune + 0.001)));
        const double sampleIndex = ageSec * sampleRate;
        const double brightness = juce::jlimit(
            0.05, 1.0, preset.cutoffHz / (preset.cutoffHz + frequencyHz * (1.5 + (1.0 - preset.tone) * 2.5)));

        auto noise = [&](int salt)
        { return hashNoise(noiseSeed + salt + (int)sampleIndex); };

        auto phaseFor = [&](double freqHz)
        { return wrapPhase(ageSec * freqHz); };

        switch (preset.family)
        {
        case InstrumentFamily::bass:
        {
            const double toneShape = juce::jlimit(0.0, 1.0, preset.tone);
            const double driveShape = juce::jlimit(0.0, 1.0, preset.drive);
            const double det = juce::jlimit(0.0, 0.012, preset.detune);
            const double punch = std::exp(-18.0 * noteProgress);
            const double pitchRatio = std::pow(
                2.0,
                juce::jlimit(0.0, 6.0, preset.pitchDropSemitones) *
                    punch / 12.0);
            const double tunedFreq = frequencyHz * pitchRatio;
            const double bodyMix =
                juce::jlimit(0.05, 0.16, 0.06 + toneShape * 0.07);
            const double secondMix =
                juce::jlimit(0.03, 0.16, 0.04 + toneShape * 0.07 + driveShape * 0.05);
            const double thirdMix =
                juce::jlimit(0.01, 0.10, 0.01 + toneShape * 0.04 + driveShape * 0.05);
            const double airMix =
                juce::jlimit(0.0, 0.05, toneShape * 0.02 + driveShape * 0.02);
            const float sub = waveFromType(0, phaseFor(tunedFreq));
            const float body = waveFromType(3, phaseFor(tunedFreq * (1.0 + det * 0.35)) + 0.125) *
                               (float)bodyMix;
            const float second = waveFromType(0, phaseFor(tunedFreq * 2.0)) *
                                 (float)secondMix;
            const float third = waveFromType(0, phaseFor(tunedFreq * 3.0)) *
                                (float)thirdMix;
            const float air = waveFromType(3, phaseFor(tunedFreq * 4.0)) *
                              (float)airMix;
            const float grit = (float)((preset.noise * (0.002 + toneShape * 0.02)) *
                                       punch * noise(23));
            const float transient = (float)((0.001 + preset.transient * 0.012 + toneShape * 0.003) *
                                            std::exp(-60.0 * noteProgress) * noise(17));
            const double core =
                sub * juce::jlimit(0.76, 0.92, 0.90 - toneShape * 0.08) +
                body + second + third + air + grit + transient;
            const double saturated =
                softSaturate(core, 1.05 + driveShape * 1.5 + toneShape * 0.35);
            const double cleanBlend =
                juce::jlimit(0.62, 0.84, 0.80 - toneShape * 0.10);
            const double shapeBlend =
                juce::jlimit(0.18, 0.40, 0.22 + toneShape * 0.10 + driveShape * 0.08);
            const double bassLevel = juce::jlimit(
                0.46, 0.98, 0.56 + brightness * 0.28 + toneShape * 0.08 + punch * 0.08);
            return (float)((sub * cleanBlend + saturated * shapeBlend) * bassLevel);
        }
        case InstrumentFamily::pad:
        {
            const double det = juce::jlimit(0.0, 0.03, preset.detune + preset.padDetuneOffset);
            const double lfo = std::sin(juce::MathConstants<double>::twoPi * ageSec * 0.23);
            const float left = waveFromType(0, phaseFor(frequencyHz * (1.0 - det)));
            const float right = waveFromType(3, phaseFor(frequencyHz * (1.0 + det)));
            const float shimmer = waveFromType(1, phaseA + 0.25) * 0.18f;
            const float airy = (float)(preset.noise * 0.55 * noise(29));
            return (left * 0.48f + right * 0.40f + shimmer + airy) *
                   (float)(brightness * juce::jlimit(0.6, 1.35, 0.85 + lfo * 0.2 + (1.0 - noteProgress) * 0.3));
        }
        case InstrumentFamily::lead:
        {
            const double vibratoRateHz = 5.1;
            const double vibratoDepth = 0.001 + 0.002 * envelope;
            const double vibratoIntegralCycles =
                (frequencyHz * vibratoDepth /
                 (juce::MathConstants<double>::twoPi * vibratoRateHz)) *
                (1.0 -
                 std::cos(juce::MathConstants<double>::twoPi * ageSec *
                          vibratoRateHz));
            const double leadPhaseA =
                wrapPhase(phaseA + vibratoIntegralCycles);
            const double leadPhaseB =
                wrapPhase(phaseB + vibratoIntegralCycles * 1.01);
            const float saw = waveFromType(1, leadPhaseA);
            const float pulse = waveFromType(2, leadPhaseB) * 0.42f;
            const float edge =
                waveFromType(3, wrapPhase(leadPhaseA * 1.99)) * 0.18f;
            const float grit = (float)(preset.noise * 0.35 * std::exp(-10.0 * noteProgress) * noise(43));
            return (saw * 0.68f + pulse + edge + grit) * (float)(brightness * (1.2 - noteProgress * 0.25));
        }
        case InstrumentFamily::pluck:
        {
            const double decay = std::exp(-6.8 * noteProgress);
            const float tri = waveFromType(3, phaseA) * 0.62f;
            const float tone = waveFromType(0, phaseB) * 0.36f;
            const float pick = (float)((preset.transient + 0.12) * std::exp(-30.0 * noteProgress) * noise(61));
            return (float)((tri + tone) * decay + pick) * (float)(brightness * (1.1 + (1.0 - noteProgress) * 0.2));
        }
        case InstrumentFamily::keys:
        {
            const int style = juce::jlimit(0, 3, preset.oscillator);
            const double keyOpen = juce::jlimit(0.6, 1.7, 0.75 + preset.tone * 0.75 + (1.0 - noteProgress) * 0.2);
            const double warmth = juce::jlimit(0.0, 1.0, 1.0 - preset.tone);
            const double tineAmount = juce::jlimit(0.04, 0.34, 0.05 + preset.transient * 0.42 + preset.tone * 0.08);
            const double chorusDepth = juce::jlimit(0.0, 0.035, preset.detune + 0.006);

            if (style == 2)
            {
                const double swirl =
                    std::sin(juce::MathConstants<double>::twoPi * ageSec *
                             5.2) *
                    chorusDepth * 0.6;
                const double octavePhase =
                    wrapPhase(ageSec * frequencyHz * 2.0);
                const double twelfthPhase =
                    wrapPhase(ageSec * frequencyHz * 3.0);
                const double fourthPhase =
                    wrapPhase(ageSec * frequencyHz * 4.0);
                const float drawbar1 = waveFromType(2, phaseA) * 0.42f;
                const float drawbar2 =
                    waveFromType(2, wrapPhase(octavePhase + swirl)) * 0.24f;
                const float drawbar3 =
                    waveFromType(2, twelfthPhase) * 0.16f;
                const float drawbar4 =
                    waveFromType(1, wrapPhase(fourthPhase - swirl)) * 0.07f;
                const float leak =
                    waveFromType(3, wrapPhase(fourthPhase * 2.0)) * 0.03f;
                const float click = (float)((0.01 + preset.transient * 0.05) * std::exp(-72.0 * noteProgress) * noise(83));
                return (drawbar1 + drawbar2 + drawbar3 + drawbar4 + leak + click) *
                       (float)(brightness * juce::jlimit(0.72, 1.08, 0.86 + preset.tone * 0.22));
            }

            if (style == 3)
            {
                const float body = waveFromType(0, phaseA) * 0.34f;
                const float tine1 = waveFromType(0, phaseFor(frequencyHz * 2.0)) * 0.22f;
                const float tine2 = waveFromType(0, phaseFor(frequencyHz * (6.2 + preset.tone * 1.6))) * (float)tineAmount;
                const float bark = waveFromType(3, phaseFor(frequencyHz * (3.0 + chorusDepth * 9.0))) * 0.10f;
                const float chorus = waveFromType(0, phaseFor(frequencyHz * (1.0 + chorusDepth))) * 0.10f;
                const float thump = (float)((0.04 + preset.transient * 0.20) * std::exp(-34.0 * noteProgress) * noise(79));
                return (body + tine1 + tine2 + bark + chorus + thump) *
                       (float)(brightness * juce::jlimit(0.76, 1.18, 0.90 + preset.tone * 0.18));
            }

            if (style == 1)
            {
                const float body = waveFromType(0, phaseA) * 0.42f;
                const float felt = waveFromType(3, phaseFor(frequencyHz * 0.5) + 0.125) * (float)(0.14 + warmth * 0.10);
                const float reed = waveFromType(1, phaseFor(frequencyHz * 2.0)) * 0.12f;
                const float bloom = waveFromType(0, phaseFor(frequencyHz * (1.0 + chorusDepth))) * 0.14f;
                const float hammer = (float)((0.06 + preset.transient * 0.16) * std::exp(-30.0 * noteProgress) * noise(75));
                return (body + felt + reed + bloom + hammer) *
                       (float)(brightness * juce::jlimit(0.74, 1.12, 0.88 + warmth * 0.16));
            }

            const double inharmonic = 1.0 + juce::jlimit(0.0, 0.008, frequencyHz * 0.0000012 + preset.transient * 0.002);
            const float hammer = (float)((0.08 + preset.transient * 0.24) * std::exp(-34.0 * noteProgress) * noise(79));
            const float body = waveFromType(0, phaseA) * (float)(0.48 + warmth * 0.10);
            const float bloom = waveFromType(3, phaseFor(frequencyHz * 0.5) + 0.125) * (float)(0.06 + warmth * 0.10);
            const float second = waveFromType(0, phaseFor(frequencyHz * 2.0 * inharmonic)) * (float)(0.18 + preset.tone * 0.10);
            const float third = waveFromType(3, phaseFor(frequencyHz * 3.0 * inharmonic)) * (float)(0.06 + preset.drive * 0.14);
            const float tine = waveFromType(0, phaseFor(frequencyHz * (4.6 + preset.tone * 2.1))) * (float)tineAmount;
            return (body + bloom + second + third + tine + hammer) *
                   (float)(brightness * juce::jlimit(0.72, 1.14, 0.84 + preset.tone * 0.16));
        }
        case InstrumentFamily::brass:
        {
            const int style = juce::jlimit(0, 3, preset.oscillator);
            const double vibDepth = 0.0011 + envelope * (0.001 + style * 0.0003);
            const double vibRate = 4.8 + style * 0.5;
            const double vibrato = 1.0 + std::sin(juce::MathConstants<double>::twoPi * ageSec * vibRate) * vibDepth;
            const float saw = waveFromType(1, phaseFor(frequencyHz * vibrato)) * 0.48f;
            const float pulse = waveFromType(2, phaseFor(frequencyHz * 0.995 * vibrato)) * 0.35f;
            const float upper = waveFromType(style >= 2 ? 1 : 0, phaseFor(frequencyHz * 2.0 * vibrato)) * (0.15f + 0.03f * (float)style);
            const float breath = (float)((0.02 + preset.noise * 0.55) * std::exp(-7.0 * noteProgress) * noise(101));
            const float formantA = waveFromType(0, phaseFor(760.0 + style * 110.0)) * 0.07f;
            const float formantB = waveFromType(0, phaseFor(1320.0 + style * 140.0)) * 0.05f;
            return (saw + pulse + upper + breath + formantA + formantB) * (float)(brightness * (0.9 + envelope * 0.45));
        }
        case InstrumentFamily::wavetable:
        {
            const double modLfo = std::sin(juce::MathConstants<double>::twoPi * ageSec * 0.35);
            const double slowModPhase = wrapPhase(ageSec * 0.27);
            const double pd = wrapPhase(
                phaseA +
                0.12 *
                    std::sin(juce::MathConstants<double>::twoPi *
                                 slowModPhase +
                             modLfo));
            const float main = (float)std::sin(juce::MathConstants<double>::twoPi * pd);
            const float upper = (float)std::sin(juce::MathConstants<double>::twoPi * pd * 2.0) * 0.33f;
            const float sparkle = waveFromType(1, pd * 1.5) * 0.22f;
            return (main + upper + sparkle) * (float)(brightness * (1.12 - noteProgress * 0.2));
        }
        case InstrumentFamily::harmonic:
        {
            const int style = juce::jlimit(0, 3, preset.oscillator);
            if (style == 3)
            {
                const double det = juce::jlimit(0.001, 0.018, preset.detune + 0.006);
                const double drift = std::sin(juce::MathConstants<double>::twoPi * ageSec * 0.18) * det;
                const double modA = std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * 1.5));
                const double modB = std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * 2.51));
                const double carrierA = wrapPhase(phaseA + modA * (0.035 + preset.tone * 0.05) + drift);
                const double carrierB = wrapPhase(phaseFor(frequencyHz * (1.0 + det)) + modB * (0.025 + preset.tone * 0.04) - drift);
                const float foundation = (float)std::sin(juce::MathConstants<double>::twoPi * carrierA) * 0.36f;
                const float bloom = (float)std::sin(juce::MathConstants<double>::twoPi * carrierB) * 0.24f;
                const float glass = (float)std::sin(2.0 * juce::MathConstants<double>::twoPi * carrierA) * 0.12f;
                const float sub = waveFromType(0, phaseFor(frequencyHz * 0.5)) * 0.10f;
                const float air = (float)((preset.noise * 0.16 + 0.01) * noise(111));
                return (foundation + bloom + glass + sub + air) *
                       (float)(brightness * juce::jlimit(0.72, 1.04, 0.80 + (1.0 - noteProgress) * 0.18));
            }

            const double modRatio = style == 0 ? 2.0 : style <= 1 ? 2.4
                                                                   : 3.0;
            const double modDepth = (style == 0 ? 0.09 : 0.05) + preset.tone * 0.13 + style * 0.02 + preset.transient * 0.04;
            const double mod = std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * modRatio));
            const double carrier = wrapPhase(phaseA + mod * modDepth);
            const double p = juce::MathConstants<double>::twoPi * carrier;
            const float body = (float)std::sin(p) * 0.46f;
            const float even = (float)std::sin(2.0 * p) * 0.22f;
            const float odd = (float)std::sin(3.0 * p) * 0.16f;
            const float air = (float)std::sin(5.0 * p) * 0.08f;
            const float bell = (style == 0)
                                   ? (float)std::sin(6.0 * p) * (float)(0.06 + preset.transient * 0.16 + preset.tone * 0.04)
                                   : 0.0f;
            const float sheen = waveFromType(style == 0 ? 2 : 3, phaseB) * (style == 0 ? 0.09f : 0.12f);
            const float transient = (float)((0.02 + preset.transient * 0.12) * std::exp(-24.0 * noteProgress) * noise(111));
            return (body + even + odd + air + bell + sheen + transient) *
                   (float)(brightness * juce::jlimit(0.82, 1.16, 0.92 + (1.0 - noteProgress) * 0.22));
        }
        case InstrumentFamily::drum:
        {
            const int kitStyle = juce::jlimit(0, 3, preset.oscillator);
            const double kitBody = juce::jlimit(0.5, 1.2, 0.62 + preset.tone * 0.55);

            if (pitch <= 36)
            {
                const double extraDrop = (kitStyle == 0 ? 22.0 : kitStyle == 1 ? 12.0 : kitStyle == 2 ? 16.0
                                                                                                         : 14.0);
                const double curve = kitStyle == 0 ? 1.35 : 1.0;
                const double dropSemis = juce::jlimit(0.0, 36.0, preset.pitchDropSemitones + extraDrop);
                const double dropProgress = std::pow(1.0 - noteProgress, curve);
                const double ratio = std::pow(2.0, -(dropSemis * dropProgress) / 12.0);
                const double tunedFreq = juce::jlimit(24.0, 1400.0, frequencyHz * ratio);
                const float body = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(tunedFreq)) * (0.80f + 0.06f * (float)kitStyle);
                const float sub = waveFromType(0, phaseFor(tunedFreq * 0.5)) * (kitStyle == 0 ? 0.36f : 0.22f);
                const float click = (float)((0.07 + preset.transient * (0.34 + kitStyle * 0.07)) * std::exp(-40.0 * noteProgress) * noise(97));
                const float beater = (float)((kitStyle == 1 || kitStyle == 2 ? 0.08 : 0.03) *
                                             std::exp(-58.0 * noteProgress) *
                                             std::sin(juce::MathConstants<double>::twoPi * phaseFor(1700.0 + frequencyHz * 4.0)));
                return (body + sub + click + beater) * (float)(brightness * kitBody);
            }
            if (pitch <= 44)
            {
                const double toneMult = kitStyle == 0 ? 1.25 : kitStyle == 1 ? 1.6 : kitStyle == 2 ? 1.85
                                                                                                      : 1.45;
                const float toneA = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * toneMult)) *
                                    (float)std::exp(-8.0 * noteProgress) * 0.36f;
                const float toneB = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * toneMult * 1.72)) *
                                    (float)std::exp(-10.0 * noteProgress) * 0.20f;
                const float noiseBurst = (float)(noise(113) * std::exp(-(9.0 + kitStyle * 1.2) * noteProgress) *
                                                 (0.55 + 0.16 * kitStyle + preset.noise * 0.55));
                return (toneA + toneB + noiseBurst) * (float)(0.66 + brightness * 0.34);
            }
            if (pitch <= 52)
            {
                if (kitStyle == 1)
                {
                    const float rimTone = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * 3.2)) *
                                          (float)std::exp(-22.0 * noteProgress) * 0.34f;
                    const float rimSnap = (float)(noise(127) * std::exp(-26.0 * noteProgress) * 0.28);
                    return rimTone + rimSnap;
                }

                const double burst0 = std::exp(-95.0 * std::pow(noteProgress - 0.028, 2.0));
                const double burst1 = std::exp(-125.0 * std::pow(noteProgress - 0.068, 2.0));
                const double burst2 = std::exp(-165.0 * std::pow(noteProgress - 0.112, 2.0));
                const double clapEnv = juce::jlimit(0.0, 1.0, burst0 + burst1 + burst2);
                const double tail = std::exp(-(10.0 + kitStyle * 1.5) * noteProgress);
                return (float)(noise(127) * (clapEnv * 0.78 + tail * 0.22));
            }
            if (pitch <= 63)
            {
                const double tomMul = kitStyle == 0 ? 0.85 : kitStyle == 1 ? 1.0 : kitStyle == 2 ? 1.18
                                                                                                    : 0.95;
                const double tomFreq = juce::jlimit(70.0, 900.0, frequencyHz * tomMul);
                const float tone = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(tomFreq)) *
                                   (float)std::exp(-6.5 * noteProgress) * 0.56f;
                const float ring = waveFromType(3, phaseFor(tomFreq * 1.6)) *
                                   (float)std::exp(-8.5 * noteProgress) * 0.24f;
                const float stick = (float)((0.03 + preset.transient * 0.14) *
                                            std::exp(-42.0 * noteProgress) * noise(141));
                return (tone + ring + stick) * (float)(0.72 + brightness * 0.28);
            }

            const double hatDecay = kitStyle == 0 ? 14.0 : kitStyle == 1 ? 18.0 : kitStyle == 2 ? 16.0
                                                                                                  : 11.0;
            const float noiseTone = (float)(noise(149) * std::exp(-hatDecay * noteProgress));
            const float metallic = waveFromType(2, phaseFor(6400.0 + kitStyle * 750.0)) * 0.23f +
                                   waveFromType(1, phaseFor(8900.0 + kitStyle * 980.0)) * 0.16f;
            const float air = waveFromType(0, phaseFor(12000.0 + kitStyle * 400.0)) * 0.06f;
            return (noiseTone + metallic + air) * (float)(0.64 + brightness * 0.36);
        }
        case InstrumentFamily::basic:
        default:
        {
            const float main = waveFromType(preset.oscillator, phaseA);
            const float sub = waveFromType(0, phaseFor(frequencyHz * 0.5)) * 0.30f;
            const float second = waveFromType(0, phaseFor(frequencyHz * 2.0)) * 0.12f;
            const float n = (float)(preset.noise * noise(11));
            return (main * 0.72f + sub + second + n) * (float)(brightness * (0.75 + preset.tone * 0.25));
        }
        }
    }

    double getTempoPlaybackRatio() const
    {
        return juce::jlimit(0.05, 20.0,
                            tempoPlaybackRatio.load(std::memory_order_relaxed));
    }

    void applyPendingLiveMidiPanic() noexcept
    {
        const auto request = liveMidiPanicRequest.exchange(
            0, std::memory_order_acq_rel);
        if (request == 0)
            return;

        LiveMidiEvent dropped;
        while (dequeueLiveMidiEventLockFree(dropped))
        {
        }
        activeLiveNotes.clear();

        const auto fullMask =
            static_cast<std::uint8_t>(LiveMidiPanicMode::full);
        if ((request & fullMask) == fullMask)
            activeTimelineNotes.reset();
    }

    void applyPendingLiveMidiEvents()
    {
        std::size_t pendingCount = 0;
        LiveMidiEvent event;
        while (pendingCount < liveMidiBlockEvents.size() &&
               dequeueLiveMidiEventLockFree(event))
        {
            liveMidiBlockEvents[pendingCount++] = event;
        }
        if (pendingCount == 0)
            return;

        const bool sampledMode =
            cachedPreset.family == InstrumentFamily::sampled &&
            cachedSampledDefinition != nullptr &&
            !cachedSampledDefinition->regions.empty();
        const double attackSec = juce::jmax(0.0, cachedPreset.attackMs / 1000.0);
        const double decaySec = juce::jmax(0.0, cachedPreset.decayMs / 1000.0);
        const double sustainLevel = juce::jlimit(0.0, 1.0, cachedPreset.sustainLevel);

        for (std::size_t eventIndex = 0; eventIndex < pendingCount; ++eventIndex)
        {
            const auto &event = liveMidiBlockEvents[eventIndex];
            if (event.noteOn && event.velocity > 0.0f)
            {
                ActiveLiveNote voice;
                voice.channel = juce::jlimit(1, 16, event.channel);
                voice.pitch = juce::jlimit(0, 127, event.pitch);
                voice.velocity = juce::jlimit(0.0, 1.0, (double)event.velocity);
                voice.ageSec = 0.0;
                voice.releasing = false;
                voice.releaseAgeSec = 0.0;
                voice.releaseStartLevel = 1.0;
                voice.seedBase = voice.pitch * 97 + voice.channel * 29 + (int)std::lround(voice.velocity * 1000.0);

                if (sampledMode)
                {
                    const auto &prepared = event.preparedSample;
                    if (!prepared.sampled ||
                        prepared.source == nullptr ||
                        prepared.source->frameCount() < 2)
                        continue;

                    voice.sampledMidiPitch = prepared.sampledMidiPitch;
                    voice.sampledSource = prepared.source;
                    voice.sampledKeyCenter = prepared.keyCenter;
                    voice.sampledGainLinear = prepared.gainLinear;
                    voice.sampledAttackSec = prepared.attackSec;
                    voice.sampledReleaseSec = prepared.releaseSec;
                    voice.sampledPitchKeytrack = prepared.pitchKeytrack;
                    voice.sampledPitchOffsetSemitones = prepared.pitchOffsetSemitones;
                    voice.sampledStartFrame = prepared.startFrame;
                    voice.sampledEndFrameExclusive = prepared.endFrameExclusive;
                    voice.sampledOneShot = prepared.oneShot;
                }

                if (activeLiveNotes.size() >= kMaxActiveLiveNotes)
                {
                    activeLiveNotes.erase(
                        activeLiveNotes.begin(),
                        activeLiveNotes.begin() +
                            (std::ptrdiff_t)(activeLiveNotes.size() - kMaxActiveLiveNotes + 1));
                }
                activeLiveNotes.push_back(voice);
                continue;
            }

            for (auto it = activeLiveNotes.rbegin(); it != activeLiveNotes.rend(); ++it)
            {
                if (it->channel != event.channel || it->pitch != event.pitch || it->releasing)
                    continue;
                if (it->sampledOneShot)
                    break;

                it->releasing = true;
                it->releaseAgeSec = 0.0;
                const double voiceAttackSec =
                    (sampledMode && it->sampledSource != nullptr &&
                     !cachedSampledAttackOverride)
                        ? juce::jmax(0.0, it->sampledAttackSec)
                        : attackSec;
                it->releaseStartLevel = envelopeHoldLevel(
                    it->ageSec,
                    voiceAttackSec,
                    decaySec,
                    sustainLevel);
                break;
            }
        }
    }

    bool enqueueLiveMidiEventLockFree(const LiveMidiEvent &event) noexcept
    {
        LiveMidiEventQueueCell *cell = nullptr;
        std::size_t position = liveMidiEnqueuePosition.load(std::memory_order_relaxed);

        for (;;)
        {
            cell = &liveMidiEventQueue[position & kLiveMidiEventQueueMask];
            const std::size_t sequence = cell->sequence.load(std::memory_order_acquire);
            const auto diff =
                static_cast<std::intptr_t>(sequence) -
                static_cast<std::intptr_t>(position);
            if (diff == 0)
            {
                if (liveMidiEnqueuePosition.compare_exchange_weak(
                        position,
                        position + 1,
                        std::memory_order_relaxed))
                    break;
            }
            else if (diff < 0)
            {
                return false;
            }
            else
            {
                position = liveMidiEnqueuePosition.load(std::memory_order_relaxed);
            }
        }

        cell->event = event;
        cell->sequence.store(position + 1, std::memory_order_release);
        return true;
    }

    bool dequeueLiveMidiEventLockFree(LiveMidiEvent &event) noexcept
    {
        LiveMidiEventQueueCell *cell = nullptr;
        std::size_t position = liveMidiDequeuePosition.load(std::memory_order_relaxed);

        for (;;)
        {
            cell = &liveMidiEventQueue[position & kLiveMidiEventQueueMask];
            const std::size_t sequence = cell->sequence.load(std::memory_order_acquire);
            const auto diff =
                static_cast<std::intptr_t>(sequence) -
                static_cast<std::intptr_t>(position + 1);
            if (diff == 0)
            {
                if (liveMidiDequeuePosition.compare_exchange_weak(
                        position,
                        position + 1,
                        std::memory_order_relaxed))
                    break;
            }
            else if (diff < 0)
            {
                return false;
            }
            else
            {
                position = liveMidiDequeuePosition.load(std::memory_order_relaxed);
            }
        }

        event = cell->event;
        cell->sequence.store(
            position + kLiveMidiEventQueueCapacity,
            std::memory_order_release);
        return true;
    }

    void refreshCachedState()
    {
        const auto *state = publishedStateRaw.load(std::memory_order_acquire);
        if (state == nullptr || state == cachedStateRaw)
            return;

        cachedStateRaw = state;
        cachedNotes = &state->renderNotes;
        cachedPreset = state->preset;
        cachedInstrumentId = state->instrumentId;
        cachedUsesDrumKitSamplePitchMap = state->usesDrumKitSamplePitchMap;
        cachedSampledDefinition = state->sampledDefinition;
        cachedSampledAttackOverride = state->sampledAttackOverride;
        cachedSampledReleaseOverride = state->sampledReleaseOverride;
        cachedSourceTempoBpm = state->sourceTempoBpm;
        activeTimelineNotes.reset();
    }

    void drainRetiredStates()
    {
        constexpr uint64_t kRetireAfterRenderGenerations = 16;
        const uint64_t currentGeneration =
            renderGeneration.load(std::memory_order_acquire);
        for (auto it = retiredStates.begin(); it != retiredStates.end();)
        {
            const bool renderGraceElapsed =
                currentGeneration >= it->retiredAtRenderGeneration &&
                (currentGeneration - it->retiredAtRenderGeneration) >=
                    kRetireAfterRenderGenerations;
            if (!renderGraceElapsed)
            {
                ++it;
                continue;
            }

            it = retiredStates.erase(it);
        }
    }

    static juce::CriticalSection &flutterAssetRootLock()
    {
        static juce::CriticalSection lock;
        return lock;
    }

    static juce::String &flutterAssetRoot()
    {
        static juce::String root;
        return root;
    }

    std::atomic<double> *blockTransportStartSec = nullptr;
    std::atomic<double> *hostSampleRate = nullptr;
    std::atomic<bool> *isPlaying = nullptr;

    std::atomic<double> clipStartSec{0.0};
    std::atomic<double> clipLengthSec{0.0};
    std::atomic<double> fileOffsetSec{0.0};
    std::atomic<float> clipGainUi{SimpleGainProcessor::kUiUnity};
    std::atomic<float> clipExtraGainLinear{1.0f};
    std::atomic<float> clipPanNormalized{0.0f};
    std::atomic<float> pitchSemitones{0.0f};
    std::atomic<double> tempoPlaybackRatio{1.0};
    std::atomic<bool> preserveTempoPitch{false};
    std::atomic<bool> muted{false};

    std::shared_ptr<const PendingState> publishedState;
    std::atomic<const PendingState *> publishedStateRaw{nullptr};
    struct RetiredPendingState
    {
        std::shared_ptr<const PendingState> state;
        uint64_t retiredAtRenderGeneration = 0;
    };
    std::vector<RetiredPendingState> retiredStates;
    std::atomic<uint64_t> renderGeneration{0};
    const PendingState *cachedStateRaw = nullptr;
    static constexpr std::size_t kLiveMidiEventQueueCapacity = 512;
    static constexpr std::size_t kLiveMidiEventQueueMask =
        kLiveMidiEventQueueCapacity - 1;
    static constexpr std::size_t kMaxActiveLiveNotes = 256;
    static constexpr std::size_t kMaxTimelineMidiNotes = 16384;
    static_assert((kLiveMidiEventQueueCapacity & kLiveMidiEventQueueMask) == 0,
                  "Live MIDI event queue capacity must be a power of two.");
    struct LiveMidiEventQueueCell
    {
        std::atomic<std::size_t> sequence{0};
        LiveMidiEvent event;
    };
    std::array<LiveMidiEventQueueCell, kLiveMidiEventQueueCapacity> liveMidiEventQueue{};
    std::array<LiveMidiEvent, kLiveMidiEventQueueCapacity> liveMidiBlockEvents{};
    std::atomic<std::size_t> liveMidiEnqueuePosition{0};
    std::atomic<std::size_t> liveMidiDequeuePosition{0};
    std::vector<ActiveLiveNote> activeLiveNotes;
    std::atomic<std::uint8_t> liveMidiPanicRequest{0};
    std::atomic<int> liveSamplePrepareSequenceCounter{0};
    std::bitset<kMaxTimelineMidiNotes> activeTimelineNotes;
    std::vector<size_t> blockNoteIndices;
    std::vector<int> blockNotePitches;
    std::vector<double> blockNoteEndSourceSecs;
    std::vector<SampledRegion> timelineRegions;
    std::atomic<double> steadyBlockStartSec{
        std::numeric_limits<double>::quiet_NaN()};
    std::atomic<bool> steadyWasPlaying{false};

    std::vector<TimelineMidiNote> emptyCachedNotes;
    const std::vector<TimelineMidiNote> *cachedNotes = &emptyCachedNotes;
    InstrumentPreset cachedPreset;
    juce::String cachedInstrumentId;
    bool cachedUsesDrumKitSamplePitchMap = false;
    std::shared_ptr<const SampledDefinition> cachedSampledDefinition;
    bool cachedSampledAttackOverride = false;
    bool cachedSampledReleaseOverride = false;
    double cachedSourceTempoBpm = 120.0;
};

// ---------------------------
// JuceEngine
// ---------------------------
class JuceEngine : public juce::MidiInputCallback,
                   public juce::ChangeListener,
                   public RoutedClipSource
{
public:
    // Mixroom route-ownership modes; these are not JUCE API versions. A
    // session selects exactly one mode before engine initialisation and never
    // falls back to the other mode in the same editor session.
    enum class AudioRouteImplementation
    {
        // No route owner has initialised the engine yet.
        none,
        // AudioDeviceManager's original self-managed route lifecycle. Retained
        // for platforms that have not adopted Mixroom's verified coordinator.
        legacy,
        // The coordinator owns serial route transitions, validates native
        // device facts, and requires a real callback before admitting audio.
        // Despite the historical name, this mode also owns recording routes.
        v2Playback,
    };

    struct ExportOptions
    {
        juce::String format{"wav"}; // "wav" | "mp3"
        double sampleRate{44100.0};
        int wavBitDepth{16};
        bool wavDithering{true};
        int mp3BitrateKbps{192};
        juce::String clipSnapshotJson;
        juce::Array<int> audibleClipIds;
        bool restrictToAudibleClipIds{false};
        bool dryClipRender{false};
        bool bypassMasterProcessing{false};
        bool bypassGroupProcessing{false};
        // Compatibility renders use an isolated offline graph. Keep the
        // realtime callback attached while that graph renders so background
        // sharing preparation cannot pause live playback.
        bool preserveRealtimePlayback{false};
        // Trim leading project silence from an offline artifact while keeping
        // the source clip's absolute placement in its caller.
        double timelineStartSeconds{0.0};
    };

    static JuceEngine &get();
    static bool isBuiltInMidiInstrumentIdentifier(const juce::String &instrumentId);

    struct PreparedMidiClipLoad;
    using PreparedMidiClipLoadPtr = std::shared_ptr<PreparedMidiClipLoad>;

    void initialiseEngine(const juce::String &v2OutputDeviceName = {},
                          double v2OutputSampleRate = 0.0,
                          int v2OutputBufferFrames = 0);
    bool initialisePlaybackV2(const juce::String &outputDeviceName,
                              double sampleRate = 0.0,
                              int bufferFrames = 0);
    bool pausePlaybackForRouteChangeV2();
    bool quiescePlaybackRouteV2(bool closeRemovedDevice);
    bool reconfigurePlaybackRouteV2(const juce::String &outputDeviceName,
                                    double sampleRate = 0.0,
                                    int bufferFrames = 0);
#if JUCE_MAC && !JUCE_IOS
    bool reconfigureMacPlaybackRouteV2(const juce::String &outputDeviceName,
                                       double sampleRate,
                                       int bufferFrames);
#endif
    void beginMacOutputCallbackProofV2() noexcept;
    bool waitForMacOutputCallbackProofV2(int timeoutMilliseconds) noexcept;
    void cancelMacOutputCallbackProofV2() noexcept;
    std::uint64_t getMacOutputCallbackProofCountV2() const noexcept;
    int getMacOutputCallbackProofFramesV2() const noexcept;
    double getMacOutputCallbackProofSampleRateV2() const noexcept;
    bool reconfigureRecordingRouteV2(const juce::String &outputDeviceName,
                                     const juce::String &inputDeviceName);
    bool prepareBluetoothDuplexSessionV2();
    bool openPreparedBluetoothDuplexRouteV2(int timeoutMilliseconds);
    bool prepareSystemSelectedDuplexSessionV2();
    bool openPreparedSystemSelectedDuplexRouteV2(int timeoutMilliseconds,
                                                 int outputChannels,
                                                 int inputChannels);
    bool reconfigureBluetoothDuplexRouteV2();
    bool validateRecordingRouteV2() const;
    bool isBluetoothDuplexProjectCallbackReadyV2() const noexcept;
    void beginIOSIntentOperationV2() noexcept;
    void endIOSIntentOperationV2() noexcept;
    void markIOSIntentRouteInvalidatedV2() noexcept;
    bool isIOSIntentOperationActiveV2() const noexcept;
    bool isIOSIntentRouteInvalidatedV2() const noexcept;
    juce::String getAudioRouteImplementationName() const;
    bool isV2PlaybackSession() const noexcept;
    bool isApplicationTerminating() const noexcept;
    void loadTrack(int idx, const juce::File &file); // deprecated name (clip)
    void removeTrack(int clipIndex);                 // removes clip
    juce::StringArray getTrackEffects(int trackIndex);
    void removePluginEffect(int trackIdx, int effectIndex);
    void reorderPluginEffects(int trackIdx, int fromIndex, int toIndex);
    void setEffectParameter(int trackIndex,
                            int effectIndex,
                            const juce::String &paramID,
                            const juce::var &newValue);
    void setTrackVolume(int trackIdx, float volume);
    double getCurrentPosition(int trackIndex);
    double getTrackDuration(int trackIndex);
    juce::Array<juce::NamedValueSet> getPluginParameterInfo(int trackIndex, int effectIndex);
    juce::String exportMix(const juce::File &outFile);
    juce::String exportMix(const juce::File &outFile, const ExportOptions &options);
    juce::String exportTrack(int trackIndex, const juce::File &outFile);
    juce::String exportTrack(int trackIndex, const juce::File &outFile, const ExportOptions &options);
    double getExportProgress() const;
    void seek(int trackIndex, double positionSeconds);
    void bypassPlugin(int trackIndex, int effectIndex, bool shouldBypass);
    bool getPluginBypassState(int trackIndex, int effectIndex);
    void bypassTrack(int trackIndex, bool shouldBypass);
    void setAdditionalPluginSearchPaths(const juce::StringArray &paths);
    juce::Array<juce::PluginDescription> getKnownPlugins();
    juce::Array<juce::PluginDescription> rescanPlugins(const juce::StringArray &paths = {});
    void cancelPluginScan();
    juce::Array<juce::NamedValueSet> getQuarantinedHostedPlugins() const;
    bool isHostedPluginQuarantined(const juce::String &pluginId) const;
    void clearHostedPluginQuarantine(const juce::String &pluginId);
    void clearAllHostedPluginQuarantines();
    juce::NamedValueSet getEngineDiagnostics();
    juce::NamedValueSet runTimelineRendererStressTest(int clipCount,
                                                      int blockCount,
                                                      int blockSize,
                                                      double sampleRate);
    void insertPluginEffect(int trackIdx, const juce::String &pluginPath, std::function<void(bool)> callback);
    void shutdownEngine();
    void shutdownForApplicationTermination();
    void panicLiveMidiNotesForApplicationDeactivation();

    // Rows
    int addRow(const juce::String &name, int iconId, int preferredRowId = -1);
    bool removeRow(int rowId);
    bool moveRowOrder(int fromIndex, int toIndex);
    int insertRowAbove(int referenceRowId, const juce::String &name, int iconId, int preferredRowId = -1);
    int insertRowBelow(int referenceRowId, const juce::String &name, int iconId, int preferredRowId = -1);
    bool renameRow(int rowId, const juce::String &newName);
    bool setRowIcon(int rowId, int iconId);
    juce::Array<juce::NamedValueSet> getRows() const;

    // Clips (stable ids)
    std::shared_ptr<DecodedClipAudioAsset> prepareClipAudioAsset(const juce::File &file);
    bool loadClipWithPreparedAudioAsset(int clipId, int rowId, const juce::File &file,
                                        std::shared_ptr<DecodedClipAudioAsset> decodedAsset,
                                        double startSec, double lengthSec, double inFileOffsetSec = 0.0);
    bool loadClip(int clipId, int rowId, const juce::File &file,
                  double startSec, double lengthSec, double inFileOffsetSec = 0.0);
    bool loadMidiClip(int clipId,
                      int rowId,
                      const juce::String &instrumentId,
                      const juce::String &instrumentName,
                      const juce::Array<TimelineMidiNote> &notes,
                      const juce::NamedValueSet &params,
                      double sourceTempoBpm,
                      double startSec,
                      double lengthSec,
                      double inFileOffsetSec = 0.0,
                      std::int64_t loadRequestId = 0);
    PreparedMidiClipLoadPtr prepareBuiltInMidiClipLoad(
        int clipId,
        int rowId,
        const juce::String &instrumentId,
        const juce::String &instrumentName,
        const juce::Array<TimelineMidiNote> &notes,
        const juce::NamedValueSet &params,
        double sourceTempoBpm,
        double startSec,
        double lengthSec,
        double inFileOffsetSec,
        std::int64_t loadRequestId);
    bool installPreparedMidiClipLoad(
        const PreparedMidiClipLoadPtr &preparedLoad);
    bool cancelMidiClipLoad(int clipId, std::int64_t loadRequestId);
    bool prepareMidiClipSampleAssets(const juce::String &instrumentId,
                                     const juce::String &instrumentName,
                                     const juce::Array<TimelineMidiNote> &notes);
    void beginProjectClipLoad();
    void endProjectClipLoad();
    void beginGraphMutationBatch();
    void endGraphMutationBatch();
    void prepareLiveClipProcessorsForCurrentDevice();
    void recordRealtimeAudioCallback(int numSamples,
                                     double sampleRate,
                                     std::int64_t elapsedTicks) noexcept;
    void beginRealtimeAudioRenderBlock() noexcept
    {
        routedAudioRenderGeneration.fetch_add(1, std::memory_order_acq_rel);
    }
    void resetRealtimePerformanceStats() noexcept;
    bool updateMidiClipEvents(int clipId,
                              const juce::String &instrumentId,
                              const juce::String &instrumentName,
                              const juce::Array<TimelineMidiNote> &notes,
                              const juce::NamedValueSet &params,
                              double sourceTempoBpm);
    bool supportsLiveMidiClipPlayback() const { return true; }
    bool playPreviewMidiNote(int clipId,
                             int pitch,
                             float velocity,
                             int durationMs);
    bool openMidiClipPluginEditor(int clipId);
    void setMidiClipPluginParameter(int clipId,
                                    const juce::String &paramId,
                                    float normalizedValue);
    void setMidiClipPluginAutomationPoints(
        int clipId,
        const juce::String &paramId,
        const std::vector<AutomationPoint> &points);
    void clearMidiClipPluginAutomation(int clipId);
    juce::String getMidiClipPluginStateBase64(int clipId);
    bool setMidiClipPluginStateBase64(int clipId, const juce::String &stateBase64);
    bool sendLiveMidiInputEvent(bool noteOn,
                                int channel,
                                int pitch,
                                float velocity);
    bool sendLiveMidiInputEventForClip(int clipId,
                                       bool noteOn,
                                       int channel,
                                       int pitch,
                                       float velocity);
    struct LiveMidiInputEvent
    {
        int clipId = -1;
        bool noteOn = false;
        int channel = 1;
        int pitch = 60;
        float velocity = 0.0f;
        double transportSec = 0.0;
        juce::AudioProcessor *routedProcessorIdentity = nullptr;
        TimelineMidiClipProcessor::PreparedLiveSample preparedSample;
    };
    bool setLiveMidiInputTargetClip(int clipId);
    std::vector<LiveMidiInputEvent> consumeLiveMidiInputEvents();
    bool unloadClip(int clipId);
    int unloadClips(const juce::Array<int> &clipIds);
    bool moveClipToRow(int clipId, int newRowId);
    bool setClipTime(int clipId, double startSec, double lengthSec, double inFileOffsetSec = 0.0);
    int updateClipTimelineBatch(const juce::Array<juce::NamedValueSet> &updates);
    int updateClipFadesBatch(const juce::Array<juce::NamedValueSet> &updates);

    // Transport
    bool play();
    void pause();
    void setTransportSeconds(double t);
    double getTransportSeconds() const;
    void setLoopRegion(bool enabled, double startSec, double endSec)
    {
        const double safeStart = juce::jmax(0.0, startSec);
        const double safeEnd = juce::jmax(safeStart, endSec);
        const bool active = enabled && safeEnd > safeStart + 1.0e-6;
        if (!active)
        {
            loopEnabledAtomic.store(false, std::memory_order_release);
            return;
        }
        loopStartSecAtomic.store(safeStart, std::memory_order_relaxed);
        loopEndSecAtomic.store(safeEnd, std::memory_order_relaxed);
        loopEnabledAtomic.store(true, std::memory_order_release);
    }
    bool isLoopRegionActive() const
    {
        return loopEnabledAtomic.load(std::memory_order_relaxed) &&
               loopEndSecAtomic.load(std::memory_order_relaxed) >
                   loopStartSecAtomic.load(std::memory_order_relaxed) + 1.0e-6;
    }
    double wrapTransportSecondsToLoop(double t) const
    {
        if (!isLoopRegionActive())
            return t;
        const double start = loopStartSecAtomic.load(std::memory_order_relaxed);
        const double end = loopEndSecAtomic.load(std::memory_order_relaxed);
        if (t < end)
            return t;
        const double length = end - start;
        if (length <= 1.0e-9)
            return start;
        double pos = std::fmod(t - start, length);
        if (pos < 0.0)
            pos += length;
        return start + pos;
    }
    void wrapPlayingTransportToLoopIfNeeded()
    {
        if (!blockIsPlayingAtomic.load(std::memory_order_relaxed) &&
            !isPlayingAtomic.load(std::memory_order_relaxed))
            return;
        const double current = transportSec.load(std::memory_order_relaxed);
        const double wrapped = wrapTransportSecondsToLoop(current);
        if (wrapped == current)
            return;
        transportSec.store(wrapped, std::memory_order_relaxed);
        mixroom::fx::setGlobalTransportSeconds(wrapped);
    }
    int samplesUntilLoopWrap(double sampleRate) const
    {
        if (sampleRate <= 0.0 || !isLoopRegionActive())
            return std::numeric_limits<int>::max();
        const double current = transportSec.load(std::memory_order_relaxed);
        const double end = loopEndSecAtomic.load(std::memory_order_relaxed);
        const double remainingSec = end - current;
        if (remainingSec <= 0.0)
            return 0;
        const double samples = remainingSec * sampleRate;
        if (samples >= (double)std::numeric_limits<int>::max())
            return std::numeric_limits<int>::max();
        return juce::jmax(1, (int)std::ceil(samples));
    }
    bool isTransportPlaying() const
    {
        return isPlayingAtomic.load(std::memory_order_relaxed);
    }
    void setBlockTransportStartFromCurrent()
    {
        const double current = transportSec.load(std::memory_order_relaxed);
        blockTransportStartSec.store(current, std::memory_order_relaxed);
        mixroom::fx::setGlobalTransportSeconds(current);
    }
    void setBlockPlayingState(bool playing)
    {
        blockIsPlayingAtomic.store(playing, std::memory_order_relaxed);
    }
    // Audio thread only; routes queued MIDI input events into clip processors.
    void dispatchQueuedLiveMidiInputEventsForAudioThread();
    void advanceTransportBySamples(int numSamples)
    {
        if (!blockIsPlayingAtomic.load(std::memory_order_relaxed))
            return;

        const double sr = hostSampleRateAtomic.load(std::memory_order_relaxed);
        if (sr <= 0.0)
            return;

        const double delta = (double)numSamples / sr;
        const double next = wrapTransportSecondsToLoop(
            transportSec.load(std::memory_order_relaxed) + delta);
        transportSec.store(next, std::memory_order_relaxed);
        mixroom::fx::setGlobalTransportSeconds(next);
    }

    void beginAudioDeviceClockV2(double sampleRate) noexcept
    {
        hostSampleRateAtomic.store(sampleRate, std::memory_order_release);
    }

    void completeGraphClockV2(double sampleRate, int bufferFrames) noexcept
    {
        graphSampleRateAtomic.store(sampleRate, std::memory_order_release);
        graphBufferFramesAtomic.store(bufferFrames, std::memory_order_release);
    }
    // (deprecated/unused) special functions for "video audio" lane
    void loadVideoAudio(const juce::File &file);
    bool loadVideoAudioWithPreparedAudioAsset(
        const juce::File &file,
        std::shared_ptr<DecodedClipAudioAsset> decodedAsset);
    void unloadVideoAudio();
    void setVideoAudioGain(float gain);
    void seekVideoAudio(double seconds);

    // Debug
    void debugPrintGraph(const juce::String &title);
    void debugPrintGraphStructure();

    // CLIP-LEVEL
    void setClipGain(int clipIndex, float gain); // gain UI ∈ 0..3 (mapped to -60..+6 dB)
    void setClipExtraGainLinear(int clipIndex, float gainLinear); // linear clip-only multiplier for normalization
    void muteClip(int clipIndex, bool shouldMute);
    void setClipPan(int clipIndex, float pan); // -1..1 where 0 = center
    void setClipFades(int clipIndex, double fadeInSec, double fadeOutSec, int fadeCurve);
    void setClipPitch(int clipIndex, float semitones); // pitch ∈ -24..24
    void setClipReversed(int clipIndex, bool shouldReverse);
    void setClipStretchOptions(int clipIndex, double tempoRatio, bool preservePitch);

    // ROW (track bus) FX
    bool insertTrackEffect(int trackRow, const juce::String &pluginPath, bool forceIndividualRow = false);
    void removeTrackEffect(int trackRow, int effectIndex, bool forceIndividualRow = false);
    void reorderTrackEffects(int trackRow, int fromIndex, int toIndex, bool forceIndividualRow = false);
    void setTrackEffectParameter(int trackRow,
                                 int effectIndex,
                                 const juce::String &paramName,
                                 const juce::var &newValue,
                                 bool forceIndividualRow = false);
    juce::StringArray getTrackEffectsForRow(int trackRow, bool forceIndividualRow = false);
    juce::StringArray getTrackEffectIdsForRow(int trackRow, bool forceIndividualRow = false);
    juce::StringArray getTrackEffectInstanceIdsForRow(int trackRow, bool forceIndividualRow = false);
    juce::String getTrackEffectStateBase64(int trackRow, int effectIndex, bool forceIndividualRow = false);
    bool setTrackEffectStateBase64(int trackRow,
                                   int effectIndex,
                                   const juce::String &stateBase64,
                                   bool forceIndividualRow = false);
    bool openTrackPluginEditor(int trackRow, int effectIndex);
    juce::Array<juce::NamedValueSet> getTrackPluginParameterInfo(int row, int effectIndex, bool forceIndividualRow = false);
    bool showHostedPluginAutomationContextMenu(const HostedPluginEditorMetadata &metadata,
                                               int contentX,
                                               int contentY);
    void requestHostedPluginAutomationForOwner(void *ownerHandle);
    void requestHostedPluginEditorCloseForOwner(void *ownerHandle);
    void setHostedPluginEditorDetachedForOwner(void *ownerHandle, bool detached);
    void bypassRowEffect(int rowIndex, int effectIndex, bool shouldBypass, bool forceIndividualRow = false);
    bool getRowEffectBypassState(int rowIndex, int effectIndex, bool forceIndividualRow = false);
    void setTrackAutomationPoints(int trackRow,
                                  const std::vector<AutomationPoint> &points);
    void setTrackEffectAutomationPoints(int trackRow,
                                        int effectIndex,
                                        const juce::String &paramId,
                                        float minValue,
                                        float maxValue,
                                        const std::vector<AutomationPoint> &points);
    void clearTrackEffectAutomationForRow(int trackRow);
    void setRowGainAutomationPoints(int row,
                                    const std::vector<AutomationPoint> &points);
    void setRowGain(int row, float gain);
    void muteRow(int rowIndex, bool shouldMute);
    bool isRowMuted(int rowIndex);
    void setRowPanAutomationPoints(int row,
                                   const std::vector<AutomationPoint> &points);
    void setRowPan(int row, float pan);

    // TRACK GROUP bus routing. A group's first rowId is treated as the visible
    // group header; row FX calls on that row are routed to the group bus.
    void configureTrackGroups(const juce::Array<juce::NamedValueSet> &groups);
    void assignRowToGroup(int row, const juce::String &groupId);
    void setTrackGroupMixState(const juce::String &groupId,
                               float gain,
                               float pan,
                               bool muted,
                               bool soloed);

    // MASTER bus FX
    bool insertMasterEffect(const juce::String &pluginPath);
    void removeMasterEffect(int effectIndex);
    void reorderMasterEffects(int fromIndex, int toIndex);
    void setMasterEffectParameter(int effectIndex,
                                  const juce::String &paramName,
                                  const juce::var &newValue);
    juce::StringArray getMasterEffects();
    juce::StringArray getMasterEffectIds();
    juce::String getMasterEffectStateBase64(int effectIndex);
    bool setMasterEffectStateBase64(int effectIndex,
                                    const juce::String &stateBase64);
    bool openMasterPluginEditor(int effectIndex);
    juce::Array<juce::NamedValueSet> getMasterPluginParameterInfo(int effectIndex);
    void bypassMasterEffect(int effectIndex, bool shouldBypass);
    bool getMasterEffectBypassState(int effectIndex);
    void setMasterEffectAutomationPoints(int effectIndex,
                                         const juce::String &paramId,
                                         float minValue,
                                         float maxValue,
                                         const std::vector<AutomationPoint> &points);
    void clearMasterEffectAutomation();
    void setMasterGainAutomationPoints(const std::vector<AutomationPoint> &points);
    void setMasterGain(float gain);
    void muteMaster(bool shouldMute);
    void setMasterPanAutomationPoints(const std::vector<AutomationPoint> &points);
    void setMasterPan(float pan);

    // Transport for automation
    void setAutomationTransport(double timeSeconds); // Dart passes seconds
    void applyTrackEffectAutomationAtCurrentBlockStart();

    void setMetronomeEnabled(bool);
    void setMetronomeVolume(float);
    void setMetronomeBpm(double);
    void setMetronomeTimeSignature(int numerator, int denominator);
    void setMetronomeTransportMs(double);

    std::vector<float> decodeAudioMono16k(const juce::File &file, int maxOutputSamples = -1);
    std::vector<std::vector<float>> sampleAudioMono16kWindows(
        const juce::File &file,
        int windowOutputSamples,
        int windowCount,
        double trimStartMs = 0.0,
        double trimEndMs = -1.0);
    juce::NamedValueSet analyzeAudioPrompt16k(
        const juce::File &file,
        double trimStartMs = 0.0,
        double trimEndMs = -1.0);
    juce::NamedValueSet analyzeAudioStereo16k(const juce::File &file);

    // Device info
    juce::StringArray getAvailableInputDevices();
    juce::StringArray getAvailableOutputDevices();
    bool selectInputDevice(const juce::String &name);
    bool selectOutputDevice(const juce::String &name);
    bool isBluetoothInputDeviceName(const juce::String &name) const;
    juce::String getCurrentInputDeviceName() const;
    juce::String getCurrentOutputDeviceName() const;
    int getNumInputChannels() const;
    void setLiveInputMonitoringEnabled(bool enabled);
    bool isLiveInputMonitoringEnabled() const noexcept;
    bool setLiveInputMonitorTargetV2(int row,
                                     int channelStart,
                                     int channelCount);
    juce::NamedValueSet getLiveInputMonitoringFactsV2();
    void discardRecordingForMonitoringV2();
    void advanceInputMonitorStreamGenerationV2() noexcept {
        inputMonitorStreamGenerationV2.fetch_add(1, std::memory_order_acq_rel);
    }
    void disableLiveInputMonitoringV2();
    bool shouldRouteLiveInputToGraphV2() const noexcept;
    bool configureAudioDevice(double sampleRate,
                              int bufferSize,
                              int desiredInputChannels,
                              const juce::String &reason);
    void setMidiInputChannelFilter(int channel) noexcept;
    int getMidiInputChannelFilter() const noexcept;
    void routeLiveInputToRow(int row, int channelCount, int channelStart = 0);
    bool prepareRecordingInputs(int desiredInputChannels,
                                const juce::String &reason);
    bool preparePlaybackRoute(const juce::String &reason);
    bool preparePlaybackGraph(const juce::String &reason);
    void prepareRecordingInputsAsync(int desiredInputChannels,
                                     const juce::String &reason);
    void refreshAudioRouteAsync(const juce::String &reason);
    void requestAudioDeviceRefreshAsync(const juce::String &reason);

    // Recording
    bool startRecordingToWav(const juce::File &file,
                             int channelStart,
                             int channelCount);
#if JUCE_MAC && !JUCE_IOS
    bool startIndependentInputRecordingToWav(const juce::File &file,
                                             double inputSampleRate,
                                             int channelCount);
    void captureIndependentInput(const float *const *inputs,
                                 int numChannels,
                                 int numSamples) noexcept;
    juce::NamedValueSet getIndependentInputCaptureFacts() const;
    bool prepareMacIndependentInputMonitoringV2(int row,
                                                int channelCount,
                                                double inputSampleRate,
                                                double outputSampleRate,
                                                int inputBlockFrames,
                                                int outputBlockFrames);
    bool publishMacIndependentInputMonitoringV2(
        const float *const *inputs,
        int numChannels,
        int numSamples) noexcept;
    void disableMacIndependentInputMonitoringV2();
    juce::NamedValueSet getMacIndependentInputMonitoringFactsV2() const;
#endif
    RealtimeWavCapture::StopResult stopRecording();
    RealtimeWavCapture::StopResult finalizeRecordingCaptureV2();
    void discardRecordingCapture();
    bool isRecording() const;
    void captureInput(const float *const *input,
                      int numInputChannels,
                      int numSamples);
    void captureOutput(float *const *output,
                       int numOutputChannels,
                       int numSamples);
    double getRecordingPeak() const;

    // Metering/Visualization
    void applyOutputSafetyGuard(float *const *output,
                                int numOutputChannels,
                                int numSamples) noexcept;
    void armOutputSafetyFadeIn(double sampleRate) noexcept;
    void setMasterMeterEnabled(bool enabled);
    const std::array<float, 4> getMasterMeterValues();
    void updateMasterMeterFromOutput(const float *const *out,
                                     int numOutCh,
                                     int numSamples) noexcept;
    // Master clip indicator (latched)
    bool getMasterClipLatched() const noexcept;
    void clearMasterClipLatched() noexcept;
    void setRowMetersEnabled(bool enabled);
    const std::array<float, 4> getRowMeterValues(int row);

    // Gets master + all row meters
    std::vector<float> getAllMeterValues() const;
    std::vector<float> getRecentMasterWaveform(int sampleCount) const;
    // Interleaved post-master samples: [L0, R0, L1, R1, ...].
    std::vector<float> getRecentMasterStereoWaveform(int sampleCount) const;

    // Compressor meter strip (white-box only)
    const std::array<float, 5> getClipCompressorMeter(int clipIndex, int effectIndex);
    const std::array<float, 5> getRowCompressorMeter(int row, int effectIndex);
    const std::array<float, 5> getMasterCompressorMeter(int effectIndex);
    double getHostSampleRate() const;
    std::vector<float> getRowEqWaveform(int row, int effectIndex, int sampleCount);
    std::vector<float> getMasterEqWaveform(int effectIndex, int sampleCount);
    std::vector<float> getRowStereoScope(int row, int effectIndex, int pointCount);
    std::vector<float> getMasterStereoScope(int effectIndex, int pointCount);
    std::vector<float> getRowShaperPreview(int row, int effectIndex, int pointCount);
    std::vector<float> getMasterShaperPreview(int effectIndex, int pointCount);
    std::vector<float> getRowDynamicSoftenerFrame(int row, int effectIndex);
    std::vector<float> getMasterDynamicSoftenerFrame(int effectIndex);
    std::vector<float> getRowTransientShaperVisual(int row, int effectIndex, int pointCount);
    std::vector<float> getMasterTransientShaperVisual(int effectIndex, int pointCount);
    void handleIncomingMidiMessage(juce::MidiInput *source,
                                   const juce::MidiMessage &message) override;
    void changeListenerCallback(juce::ChangeBroadcaster *source) override;
    void processRoutedClipsForRow(int rowId,
                                  const void *rowSchedule,
                                  juce::AudioBuffer<float> &buffer,
                                  juce::MidiBuffer &midi,
                                  juce::AudioBuffer<float> &scratchBuffer,
                                  juce::MidiBuffer &scratchMidi) override;

private:
    JuceEngine();
    ~JuceEngine();

    void rewireTrackChain(int trackIdx,
                          juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync); // clip-level FX+gain+pan → row
    void rewireMasterFxChain(
        juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync,
        bool callerHoldsGraphLock = false); // master FX chain
    void rebuildClipProcessorsFromStoredStateLocked(
        juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::none);
    void reapplyClipProcessorStateLocked();
    void primeClipProcessorsForOfflineRenderLocked();
    std::shared_ptr<DecodedClipAudioAsset> getOrDecodeClipAudioAsset(const juce::File &file);
    bool isMidiClipLoadRequestCancelled(int clipId,
                                        std::int64_t loadRequestId);
    void requestLiveMidiPanicForClip(int clipId,
                                     LiveMidiPanicMode mode) noexcept;
    void requestLiveMidiPanicForAll(LiveMidiPanicMode mode) noexcept;
    void armOutputSafetyForCurrentRoute() noexcept;
    void armOutputSafetyForCurrentRouteLocked() noexcept;
    void ensureBusGraphInitialised(bool commitImmediately = true); // rows + master
    void commitClipGraphMutationLocked(bool armOutputSafety = true) noexcept;
    void rewireTrackBusFxChain(
        int trackRow,
        juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync,
        bool callerHoldsGraphLock = false); // row-level FX between input and automation
    void rewireTrackGroupFxChain(
        const juce::String &groupId,
        juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync,
        bool callerHoldsGraphLock = false);
    void markGraphMutationBatchRowFxDirtyLocked(int rowIndex);
    void markGraphMutationBatchTrackGroupFxDirtyLocked(const juce::String &groupId);
    void markGraphMutationBatchMasterFxDirtyLocked();
    void flushGraphMutationBatchFxRewiresLocked();
    void reconnectAllRowOutputsToBuses(
        juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync);
    int getTrackIndexForClip(int clipIdx) const; // clip → row mapping
    bool enqueueLiveMidiInputAudioEvent(const LiveMidiInputEvent &event) noexcept;
    bool dequeueLiveMidiInputAudioEvent(LiveMidiInputEvent &event) noexcept;
    bool prepareLiveMidiInputEventForAudioQueue(LiveMidiInputEvent &event);
    void clearLiveMidiInputAudioQueue() noexcept;
    bool attachAudioCallbackIfAllowed(juce::AudioIODeviceCallback *callback);
    float panUIToNormalized(float uiPan)         // OLD: uiPan ∈ [-1, 1] NEW: uiPan ∈ [0, 1]
    {
        // return juce::jmap(uiPan, -1.0f, 1.0f, 0.0f, 1.0f); // map to [0, 1]
        return juce::jmap(uiPan, 0.0f, 1.0f, 0.0f, 1.0f); // map to [0, 1] (basically does nothing, just clamp)
    }

    static const juce::StringArray mixroomPlugins;

    bool engineInitialized = false;
    std::atomic<bool> applicationTerminationStarted{false};
    std::mutex engineLifecycleMutex;
    std::atomic<std::uint64_t> engineLifecycleGeneration{1};
    std::atomic<uint64_t> inputMonitorStreamGenerationV2{1};
    bool formatsRegistered = false; // will only be flipped once to true
    AudioRouteImplementation audioRouteImplementation =
        AudioRouteImplementation::none;
    bool v2PlaybackCallbackDetached = false;
    std::atomic<bool> iosIntentOperationActiveV2{false};
    std::atomic<bool> iosIntentRouteInvalidatedV2{false};
    std::unique_ptr<IOSBluetoothDuplexProbeCallback>
        iosBluetoothDuplexProbeCallback;
    bool iosBluetoothDuplexProbeCallbackAttached = false;
    void detachIOSBluetoothDuplexProbeCallback() noexcept;
    bool openPlaybackOutputOnlyV2(const juce::String &outputDeviceName,
                                  double preferredSampleRate = 0.0,
                                  int preferredBufferFrames = 0);
    bool openRecordingInputV2(const juce::String &outputDeviceName,
                              const juce::String &inputDeviceName,
                              bool bluetoothHfp = false);
    juce::AudioFormatManager formatManager;
    juce::AudioPluginFormatManager pluginFormatManager;
    juce::AudioProcessorGraph graph;
    juce::AudioProcessorGraph exportGraph;

    juce::AudioProcessorGraph::Node::Ptr inputNode;
    juce::AudioProcessorGraph::Node::Ptr outputNode;

    // Legacy clip containers still used by compatibility code paths.
    juce::Array<juce::AudioProcessorGraph::Node::Ptr> trackNodes;
    juce::Array<SimpleGainProcessor *> gainProcessors;
    juce::OwnedArray<juce::Array<juce::AudioProcessorGraph::NodeID>> trackEffectChains;

    juce::KnownPluginList pluginList;
    juce::StringArray pluginScanFailures;
    juce::StringArray additionalPluginSearchPaths;
    void scanPluginsIfNeeded();
    void performPluginScan(bool reuseUnchangedPlugins = false);
    bool restoreCachedPluginList();
    void persistPluginListCache() const;
    bool pluginsScanned = false;
    std::atomic<bool> pluginScanCancellationRequested{false};
    std::vector<juce::String> getExposedParametersForPlugin(const juce::String &pluginId);

    juce::AudioDeviceManager deviceManager;
    juce::AudioProcessorPlayer audioPlayer;

    // (deprecated/unused) Playback-only "video audio" lane (excluded from exports)
    juce::AudioProcessorGraph::Node::Ptr videoAudioNode{nullptr};
    SimpleGainProcessor *videoGainProc{nullptr};
    bool hasVideoAudio{false};

    std::atomic<double> transportSec{0.0};           // source of truth
    std::atomic<bool> loopEnabledAtomic{false};
    std::atomic<double> loopStartSecAtomic{0.0};
    std::atomic<double> loopEndSecAtomic{0.0};
    std::atomic<double> blockTransportStartSec{0.0}; // set each audio callback block
    std::atomic<double> hostSampleRateAtomic{44100.0};
    std::atomic<double> graphSampleRateAtomic{0.0};
    std::atomic<int> graphBufferFramesAtomic{0};
    std::atomic<double> preferredAudioSampleRate{44100.0};
    std::atomic<int> preferredAudioBufferSize{512};
    std::atomic<bool> isPlayingAtomic{false};
    std::atomic<bool> blockIsPlayingAtomic{false};
    std::atomic<double> exportProgressAtomic{0.0};
    std::atomic<bool> exportInProgressAtomic{false};
    std::atomic<int> liveMidiInputTargetClip{-1};
    std::mutex liveMidiInputQueueMutex;
    std::vector<LiveMidiInputEvent> liveMidiInputPendingForFlutter;
    static constexpr std::size_t kLiveMidiInputAudioQueueCapacity = 4096;
    static constexpr std::size_t kLiveMidiInputAudioQueueMask = kLiveMidiInputAudioQueueCapacity - 1;
    static_assert((kLiveMidiInputAudioQueueCapacity & kLiveMidiInputAudioQueueMask) == 0,
                  "Live MIDI input queue capacity must be a power of two");
    struct LiveMidiInputAudioQueueCell
    {
        std::atomic<std::size_t> sequence{0};
        LiveMidiInputEvent event;
    };
    std::array<LiveMidiInputAudioQueueCell, kLiveMidiInputAudioQueueCapacity> liveMidiInputAudioQueue{};
    std::array<LiveMidiInputEvent, kLiveMidiInputAudioQueueCapacity> liveMidiInputAudioBlockEvents{};
    std::atomic<std::size_t> liveMidiInputAudioEnqueuePosition{0};
    std::atomic<std::size_t> liveMidiInputAudioDequeuePosition{0};
    std::vector<juce::String> midiInputCallbackDeviceIds;
    std::atomic<bool> midiInputCallbacksInitialized{false};
    std::atomic<int> midiInputChannelFilter{0};

    // Basic limits
    static constexpr int kNumTracks = 5;  // legacy fixed-row compatibility paths
    static constexpr int kMaxRows = 100;  // hard safety cap
    static constexpr int kMaxClips = 500; // safety cap for simultaneous clips
    static constexpr float kGainUiMin = 0.0f;
    static constexpr float kGainUiMax = 3.0f;
    static constexpr float kGainDbMin = -60.0f;
    static constexpr float kGainDbMax = 6.0f;
    static constexpr float kGainUiUnity = 2.0f;

    // Legacy row/clip routing containers retained for compatibility.
    juce::Array<StereoPanProcessor *> clipPanProcessors;
    juce::Array<int> clipTrackAssignments;

    TrackInputProcessor *trackInputProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackInputNodes[kNumTracks];

    juce::OwnedArray<juce::Array<juce::AudioProcessorGraph::NodeID>> trackBusEffectChains;

    VolumeAutomationProcessor *trackAutomationProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackAutomationNodes[kNumTracks];

    SimpleGainProcessor *trackGainProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackGainNodes[kNumTracks];

    StereoPanProcessor *trackPanProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackPanNodes[kNumTracks];

    struct ClipState
    {
        bool alive = false;
        bool wired = false;
        bool isMidi = false;
        bool muted = false;

        int clipId = -1; // stable
        int rowId = 0;   // stable row id

        // timeline
        double startSec = 0.0;
        double lengthSec = 0.0;
        double inFileOffsetSec = 0.0; // == trimStart. optional later for trimming
        float pitchSemitones = 0.0f;
        bool reversed = false;
        double tempoRatio = 1.0;
        bool preservePitch = false;
        float gainUi = kGainUiUnity;
        float extraGainLinear = 1.0f;
        float panNormalized = 0.0f;
        double fadeInSec = 0.0;
        double fadeOutSec = 0.0;
        int fadeCurve = 0;

        // authoritative source state used to rebuild fresh player nodes
        juce::String sourceFilePath;
        juce::String midiInstrumentId;
        juce::String midiInstrumentName;
        juce::Array<TimelineMidiNote> midiNotes;
        juce::NamedValueSet midiParams;
        double midiSourceTempoBpm = 120.0;
        std::int64_t midiLoadRequestId = 0;
        juce::MemoryBlock midiPluginState;

        // nodes/processors
        std::shared_ptr<juce::AudioProcessor> playerProcessor; // live timeline processor, mixed by row input
        juce::AudioProcessorGraph::Node::Ptr playerNode;       // legacy/export/hosted plugin fallback
        juce::Array<juce::AudioProcessorGraph::NodeID> fxChain; // clip-level legacy FX
        int lastRowInputNodeUid = 0;                            // cached destination for fast rewires
    };

    struct RetiredLiveClipProcessor
    {
        std::shared_ptr<juce::AudioProcessor> processor;
        uint64_t retiredAtRenderGeneration = 0;
    };

    struct RoutedClipRenderItem
    {
        int clipId = -1;
        int rowId = 0;
        bool isMidi = false;
        double startSec = 0.0;
        double endSec = 0.0;
        std::shared_ptr<juce::AudioProcessor> processor;
    };

    struct MutableRowRoutedClipSchedule
    {
        std::unordered_map<long long, std::vector<RoutedClipRenderItem>> bucketItems;
        std::unordered_map<int, RoutedClipRenderItem> clipItemsById;
    };

    struct RoutedClipBucketItems
    {
        long long bucket = 0;
        std::vector<RoutedClipRenderItem> items;
    };

    struct RowRoutedClipSchedule
    {
        std::vector<RoutedClipBucketItems> bucketItems;
        std::array<RoutedClipRenderItem, kMaxClips> clipItemsById{};
        std::bitset<kMaxClips> clipItemPresent;

        const RoutedClipRenderItem *findClip(int clipId) const noexcept
        {
            if (clipId < 0 || clipId >= kMaxClips)
                return nullptr;
            const auto index = static_cast<size_t>(clipId);
            return clipItemPresent.test(index) ? &clipItemsById[index] : nullptr;
        }
    };

    using RowRoutedClipSchedulePtr = std::shared_ptr<const RowRoutedClipSchedule>;
    using RoutedClipSchedules = std::unordered_map<int, RowRoutedClipSchedulePtr>;
    using MutableRoutedClipSchedules = std::unordered_map<int, MutableRowRoutedClipSchedule>;
    using RoutedClipItemsById = std::unordered_map<int, RoutedClipRenderItem>;

    struct RoutedClipItemsSnapshot
    {
        std::array<RoutedClipRenderItem, kMaxClips> itemsById{};
        std::bitset<kMaxClips> itemPresent;

        const RoutedClipRenderItem *findClip(int clipId) const noexcept
        {
            if (clipId < 0 || clipId >= kMaxClips)
                return nullptr;
            const auto index = static_cast<size_t>(clipId);
            return itemPresent.test(index) ? &itemsById[index] : nullptr;
        }
    };

    struct RetiredRoutedClipScheduleSnapshot
    {
        std::shared_ptr<const RoutedClipSchedules> snapshot;
        uint64_t retiredAtRenderGeneration = 0;
    };

    struct RetiredRoutedClipItemSnapshot
    {
        std::shared_ptr<const RoutedClipItemsSnapshot> snapshot;
        uint64_t retiredAtRenderGeneration = 0;
    };

    // fixed slots so ids never shift
    std::vector<ClipState> clips;
    std::mutex midiLoadRequestMutex;
    std::unordered_map<int, std::int64_t> cancelledMidiLoadRequestThrough;
    MutableRoutedClipSchedules rowRoutedClipSchedules;
    std::unordered_set<int> dirtyRoutedClipScheduleRows;
    RoutedClipItemsById routedClipItemsById;
    std::shared_ptr<const RoutedClipSchedules> rowRoutedClipScheduleSnapshot;
    std::shared_ptr<const RoutedClipItemsSnapshot> routedClipItemSnapshot;
    std::atomic<const RoutedClipItemsSnapshot *> routedClipItemSnapshotRaw{nullptr};
    std::vector<RetiredLiveClipProcessor> retiredLiveClipProcessors;
    std::vector<RetiredRoutedClipScheduleSnapshot> retiredRoutedClipScheduleSnapshots;
    std::vector<RetiredRoutedClipItemSnapshot> retiredRoutedClipItemSnapshots;
    std::atomic<uint64_t> routedAudioRenderGeneration{0};
    std::mutex decodedClipAssetCacheMutex;
    std::unordered_map<std::string, std::weak_ptr<DecodedClipAudioAsset>> decodedClipAssetCache;

    // METERING
    struct StereoMeterState
    {
        std::atomic<float> peakL{0.0f};
        std::atomic<float> peakR{0.0f};
        std::atomic<float> rmsL{0.0f};
        std::atomic<float> rmsR{0.0f};

        StereoMeterState() = default;

        StereoMeterState(const StereoMeterState &other)
        {
            peakL.store(other.peakL.load(std::memory_order_relaxed), std::memory_order_relaxed);
            peakR.store(other.peakR.load(std::memory_order_relaxed), std::memory_order_relaxed);
            rmsL.store(other.rmsL.load(std::memory_order_relaxed), std::memory_order_relaxed);
            rmsR.store(other.rmsR.load(std::memory_order_relaxed), std::memory_order_relaxed);
        }

        StereoMeterState &operator=(const StereoMeterState &other)
        {
            if (this != &other)
            {
                peakL.store(other.peakL.load(std::memory_order_relaxed), std::memory_order_relaxed);
                peakR.store(other.peakR.load(std::memory_order_relaxed), std::memory_order_relaxed);
                rmsL.store(other.rmsL.load(std::memory_order_relaxed), std::memory_order_relaxed);
                rmsR.store(other.rmsR.load(std::memory_order_relaxed), std::memory_order_relaxed);
            }
            return *this;
        }

        StereoMeterState(StereoMeterState &&other) noexcept
        {
            peakL.store(other.peakL.load(std::memory_order_relaxed), std::memory_order_relaxed);
            peakR.store(other.peakR.load(std::memory_order_relaxed), std::memory_order_relaxed);
            rmsL.store(other.rmsL.load(std::memory_order_relaxed), std::memory_order_relaxed);
            rmsR.store(other.rmsR.load(std::memory_order_relaxed), std::memory_order_relaxed);
        }

        StereoMeterState &operator=(StereoMeterState &&other) noexcept
        {
            if (this != &other)
            {
                peakL.store(other.peakL.load(std::memory_order_relaxed), std::memory_order_relaxed);
                peakR.store(other.peakR.load(std::memory_order_relaxed), std::memory_order_relaxed);
                rmsL.store(other.rmsL.load(std::memory_order_relaxed), std::memory_order_relaxed);
                rmsR.store(other.rmsR.load(std::memory_order_relaxed), std::memory_order_relaxed);
            }
            return *this;
        }
    };
    StereoMeterState masterMeter;
    std::atomic<bool> masterMeterEnabled{true};
    std::atomic<bool> masterClipLatched{false};
    static constexpr int kMasterWaveformRingSize = 8192;
    std::array<float, kMasterWaveformRingSize> masterWaveformRingL{};
    std::array<float, kMasterWaveformRingSize> masterWaveformRingR{};
    std::atomic<int> masterWaveformWritePos{0};
    std::array<float, 2> outputSafetyLastSample{0.0f, 0.0f};
    int outputSafetyMuteSamplesRemaining = 0;
    int outputSafetyFadeSamplesRemaining = 0;
    int outputSafetyFadeSamplesTotal = 0;
    std::atomic<int> outputSafetyControlRequest{0};
    std::atomic<int> outputSafetyRequestedFadeSamples{0};
    static constexpr int kOutputSafetyRequestClear = 1;
    static constexpr int kOutputSafetyRequestFadeIn = 2;

    // Row meters (post row-pan)
    std::atomic<bool> rowMetersEnabled{true};
    MeterTapProcessor *rowMeterTaps[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr rowMeterTapNodes[kNumTracks];

    struct RowState
    {
        struct TrackEffectAutomationLane
        {
            int effectIndex = -1;
            juce::String paramId;
            float minValue = 0.0f;
            float maxValue = 1.0f;
            std::vector<AutomationPoint> points;
            float lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
        };

        int rowId = 0; // stable id
        juce::String name = "Row";
        int iconId = 0;      // UI icon enum/int
        float gainUi = kGainUiUnity; // 0..3 UI domain, piecewise taper with unity at 2.0
        float panUi = 0.5f;  // 0..1 UI domain
        bool muted = false;
        std::vector<AutomationPoint> automationPoints;
        std::vector<AutomationPoint> gainAutomationPoints;
        std::vector<AutomationPoint> panAutomationPoints;
        std::vector<TrackEffectAutomationLane> effectAutomationLanes;
        float lastAppliedGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
        float lastAppliedPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();

        // processors
        TrackInputProcessor *inputProc = nullptr;
        VolumeAutomationProcessor *automationProc = nullptr;
        SimpleGainProcessor *gainProc = nullptr;
        StereoPanProcessor *panProc = nullptr;
        MeterTapProcessor *meterTapProc = nullptr;

        // nodes
        juce::AudioProcessorGraph::Node::Ptr inputNode;
        juce::AudioProcessorGraph::Node::Ptr automationNode;
        juce::AudioProcessorGraph::Node::Ptr gainNode;
        juce::AudioProcessorGraph::Node::Ptr panNode;
        juce::AudioProcessorGraph::Node::Ptr meterTapNode;

        // FX chain node ids (row-level FX between input and automation)
        juce::Array<juce::AudioProcessorGraph::NodeID> fxChain;
        juce::StringArray fxIds;

        std::shared_ptr<StereoMeterState> meter = std::make_shared<StereoMeterState>();
    };

    struct AutomationLatchState
    {
        AutomationLatchState() { reset(); }

        void reset() noexcept
        {
            lastAppliedGainNormalized.store(
                std::numeric_limits<float>::quiet_NaN(),
                std::memory_order_relaxed);
            lastAppliedPanNormalized.store(
                std::numeric_limits<float>::quiet_NaN(),
                std::memory_order_relaxed);
        }

        std::atomic<float> lastAppliedGainNormalized;
        std::atomic<float> lastAppliedPanNormalized;
    };

    struct AutomationLaneLatch
    {
        AutomationLaneLatch() { reset(); }

        void reset() noexcept
        {
            lastAppliedNormalized.store(
                std::numeric_limits<float>::quiet_NaN(),
                std::memory_order_relaxed);
        }

        std::atomic<float> lastAppliedNormalized;
    };

    struct AutomationParameterTarget
    {
        enum class RealtimeWriteKind
        {
            none,
            floatActual,
            boolNormalized,
            choiceNormalized,
            normalized
        };

        juce::AudioProcessorGraph::Node::Ptr node;
        std::shared_ptr<juce::AudioProcessor> processorOwner;
        juce::AudioProcessorParameter *parameter = nullptr;
        std::atomic<float> *realtimeRawValue = nullptr;
        bool usesFloatRange = false;
        juce::NormalisableRange<float> floatRange;
        RealtimeWriteKind realtimeWriteKind = RealtimeWriteKind::none;
        int realtimeChoiceMaxIndex = 0;

        bool isValid() const noexcept
        {
            return (node != nullptr || processorOwner != nullptr) &&
                   parameter != nullptr;
        }
    };

    struct AutomationEffectLaneSnapshot
    {
        int effectIndex = -1;
        juce::String paramId;
        float minValue = 0.0f;
        float maxValue = 1.0f;
        std::vector<AutomationPoint> points;
        AutomationParameterTarget target;
        std::shared_ptr<AutomationLaneLatch> latch;
    };

    struct RowAutomationSnapshot
    {
        int rowIndex = -1;
        int rowId = 0;
        std::vector<AutomationPoint> gainAutomationPoints;
        std::vector<AutomationPoint> panAutomationPoints;
        AutomationParameterTarget gainTarget;
        AutomationParameterTarget panTarget;
        bool muted = false;
        std::vector<AutomationEffectLaneSnapshot> effectAutomationLanes;
        std::shared_ptr<AutomationLatchState> latches;
    };

    struct AutomationSnapshot
    {
        std::vector<RowAutomationSnapshot> rows;
        std::vector<AutomationPoint> masterGainAutomationPoints;
        std::vector<AutomationPoint> masterPanAutomationPoints;
        AutomationParameterTarget masterGainTarget;
        AutomationParameterTarget masterPanTarget;
        bool masterMuted = false;
        std::vector<AutomationEffectLaneSnapshot> masterEffectAutomationLanes;
        std::vector<AutomationEffectLaneSnapshot> midiClipPluginAutomationLanes;
        std::shared_ptr<AutomationLatchState> masterLatches;
    };

    struct RetiredAutomationSnapshot
    {
        std::shared_ptr<const AutomationSnapshot> snapshot;
        uint64_t retiredAtRenderGeneration = 0;
    };

    struct TrackGroupState
    {
        juce::String id;
        juce::Array<int> rowIds;
        float gainUi = kGainUiUnity;
        float panUi = 0.5f;
        bool muted = false;
        bool soloed = false;

        TrackInputProcessor *inputProc = nullptr;
        SimpleGainProcessor *gainProc = nullptr;
        StereoPanProcessor *panProc = nullptr;
        MeterTapProcessor *meterTapProc = nullptr;
        juce::AudioProcessorGraph::Node::Ptr inputNode;
        juce::AudioProcessorGraph::Node::Ptr gainNode;
        juce::AudioProcessorGraph::Node::Ptr panNode;
        juce::AudioProcessorGraph::Node::Ptr meterTapNode;
        juce::Array<juce::AudioProcessorGraph::NodeID> fxChain;
        juce::StringArray fxIds;
        std::shared_ptr<StereoMeterState> meter = std::make_shared<StereoMeterState>();
    };

    struct MeterReadoutSnapshot
    {
        std::vector<std::shared_ptr<StereoMeterState>> rowMeters;
    };

    // row storage
    std::vector<RowState> rows;
    std::unordered_map<int, int> rowIdToIndex;
    std::unordered_map<int, juce::Array<int>> rowIdToClipIds;
    std::vector<TrackGroupState> trackGroups;
    std::shared_ptr<const MeterReadoutSnapshot> meterReadoutSnapshot;
    std::unordered_map<std::string, std::unique_ptr<HostedPluginEditorWindow>> hostedPluginEditorWindows;
    std::atomic<int> nextRowId{1};
    int allocateRowId(int preferredRowId);

    // MASTER bus: rows → master input → [FX...] → gain → pan → output
    juce::Array<juce::AudioProcessorGraph::NodeID> *masterEffectChain = nullptr;
    juce::StringArray masterEffectIds;
    std::vector<RowState::TrackEffectAutomationLane> masterEffectAutomationLanes;
    std::vector<RowState::TrackEffectAutomationLane> midiClipPluginAutomationLanes;
    std::vector<AutomationPoint> masterGainAutomationPoints;
    std::vector<AutomationPoint> masterPanAutomationPoints;
    float lastAppliedMasterGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    float lastAppliedMasterPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    std::shared_ptr<const AutomationSnapshot> automationSnapshot;
    std::atomic<const AutomationSnapshot *> automationSnapshotRaw{nullptr};
    std::vector<RetiredAutomationSnapshot> retiredAutomationSnapshots;
    std::unordered_map<int, std::shared_ptr<AutomationLatchState>> rowAutomationLatches;
    std::unordered_map<std::string, std::shared_ptr<AutomationLaneLatch>> automationLaneLatches;
    std::shared_ptr<AutomationLatchState> masterAutomationLatches =
        std::make_shared<AutomationLatchState>();

    TrackInputProcessor *masterInputProcessor = nullptr;
    juce::AudioProcessorGraph::Node::Ptr masterInputNode;

    SimpleGainProcessor *masterGainProcessor = nullptr;
    juce::AudioProcessorGraph::Node::Ptr masterGainNode;

    StereoPanProcessor *masterPanProcessor = nullptr;
    juce::AudioProcessorGraph::Node::Ptr masterPanNode;
    float masterGainUi = kGainUiUnity;
    float masterPanUi = 0.5f;
    bool masterMuted = false;

    bool busGraphInitialised = false;
    TrackGroupState *trackGroupForId(const juce::String &groupId);
    const TrackGroupState *trackGroupForId(const juce::String &groupId) const;
    TrackGroupState *trackGroupForLeadRowIndex(int rowIndex);
    const TrackGroupState *trackGroupForLeadRowIndex(int rowIndex) const;
    TrackGroupState *trackGroupForMemberRowId(int rowId);
    void attachTrackGroupBusNodes(TrackGroupState &group,
                                  juce::AudioProcessorGraph::UpdateKind updateKind,
                                  bool callerHoldsGraphLock = false);
    void ensureTrackGroupBusNodesAttached(TrackGroupState &group,
                                          juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync,
                                          bool callerHoldsGraphLock = false);
    void compactTrackGroupFxChain(TrackGroupState &group);
    juce::Array<juce::AudioProcessorGraph::NodeID> *effectChainForRowApi(int rowIndex, bool forceIndividualRow = false);
    juce::StringArray *effectIdsForRowApi(int rowIndex, bool forceIndividualRow = false);

    std::unique_ptr<MetronomeAudioCallback> metronomeCallback;

    // Recording state
    RealtimeWavCapture wavCapture;
    std::atomic<bool> independentInputCaptureMode{false};
    std::atomic<int> recordingRestoreDesiredInputs{0};
    std::atomic<int> desiredInputOpenChannels{0};
    juce::String preferredInputDeviceName;
    std::atomic<bool> audioRouteRefreshPending{false};
    std::atomic<int> ignoredDeviceChangeCallbacks{0};
    bool liveInputMonitoringEnabled = true;
    std::atomic<bool> liveInputMonitoringActiveV2{false};
    int liveMonitorTargetRow = 0;
    int liveMonitorChannelCount = 0;
    int liveMonitorChannelStart = 0;
    juce::Array<juce::AudioProcessorGraph::Connection> liveMonitorConnections;
#if JUCE_MAC && !JUCE_IOS
    MacIndependentMonitorBuffer macIndependentMonitorBuffer;
    juce::AudioProcessorGraph::Node::Ptr macIndependentMonitorSourceNode;
    juce::Array<juce::AudioProcessorGraph::Connection>
        macIndependentMonitorConnections;
#endif

    void pushMasterWaveformSamples(const float *const *out,
                                   int numOutCh,
                                   int numSamples) noexcept;
    int projectClipLoadDepth = 0;
    bool projectClipLoadNeedsGraphRebuild = false;
    bool projectClipLoadNeedsOutputSafety = false;
    bool projectClipLoadDetachedAudioCallback = false;
    int graphMutationBatchDepth = 0;
    bool graphMutationBatchNeedsRebuild = false;
    bool graphMutationBatchNeedsOutputSafety = false;
    std::unordered_set<int> graphMutationBatchDirtyRowFxChains;
    juce::StringArray graphMutationBatchDirtyTrackGroupFxChains;
    bool graphMutationBatchDirtyMasterFxChain = false;
    int routedClipScheduleMutationDepth = 0;
    bool routedClipSchedulePublishPending = false;
    // Recursive because public graph mutation entrypoints can call one another.
    std::recursive_mutex graphRenderMutex;
    std::atomic<std::int64_t> realtimeTicksPerSecond{0};
    std::atomic<std::uint64_t> realtimeCallbackCount{0};
    std::atomic<std::uint64_t> realtimeCallbackTotalTicks{0};
    std::atomic<std::int64_t> realtimeCallbackLastTicks{0};
    std::atomic<std::int64_t> realtimeCallbackMaxTicks{0};
    std::atomic<std::uint64_t> realtimeCallbackOverBudgetCount{0};
    std::atomic<int> realtimeCallbackMaxSamples{0};
    std::atomic<std::uint64_t> graphRebuildImmediateCount{0};
    std::atomic<std::uint64_t> graphRebuildDeferredCount{0};
    std::atomic<std::uint64_t> graphRebuildBatchCommitCount{0};
    std::atomic<std::uint64_t> graphRebuildProjectLoadCommitCount{0};
    void recordGraphRebuildRequest(bool deferred,
                                   bool batchCommit,
                                   bool projectLoadCommit) noexcept;
    bool openPluginEditorWindowForNode(juce::AudioProcessorGraph::NodeID nodeID,
                                       const juce::String &titlePrefix,
                                       HostedPluginEditorMetadata metadata = {},
                                       bool showInitially = true);
    void closePluginEditorWindowForNode(juce::AudioProcessorGraph::NodeID nodeID);
    bool openPluginEditorWindowForProcessor(const std::string &key,
                                            juce::AudioProcessor &processor,
                                            const juce::String &titlePrefix,
                                            HostedPluginEditorMetadata metadata = {},
                                            bool showInitially = true);
    void closePluginEditorWindowForKey(const std::string &key);
    static std::string pluginEditorWindowKeyForClip(int clipId);
    void closeHostedPluginEditorWindowsForRow(const RowState &row);
    void closeAllHostedPluginEditorWindows();
    struct GraphMutationScope
    {
        GraphMutationScope(juce::CriticalSection &audioCallbackLock,
                           std::recursive_mutex &renderMutex)
            : callbackLock(audioCallbackLock),
              renderLock(renderMutex)
        {
        }

    private:
        juce::GenericScopedLock<juce::CriticalSection> callbackLock;
        std::unique_lock<std::recursive_mutex> renderLock;
    };

    void rebuildBusesAndRewireClips();
    void commitGraphMutationLocked(bool armOutputSafety = true) noexcept;
    std::shared_ptr<AutomationLatchState> rowAutomationLatchesLocked(int rowId);
    std::shared_ptr<AutomationLaneLatch> automationLaneLatchLocked(const std::string &key);
    static std::string automationLaneKeyForRow(int rowId, int effectIndex, const juce::String &paramId);
    static std::string automationLaneKeyForMaster(int effectIndex, const juce::String &paramId);
    AutomationParameterTarget resolveTrackAutomationParameterTargetLocked(
        int rowIndex,
        int effectIndex,
        const juce::String &paramId);
    AutomationParameterTarget resolveMasterAutomationParameterTargetLocked(
        int effectIndex,
        const juce::String &paramId);
    AutomationParameterTarget resolveMidiClipAutomationParameterTargetLocked(
        int clipId,
        const juce::String &paramId);
    static bool automationParameterMatches(
        juce::AudioProcessorParameter &parameter,
        const juce::String &paramId);
    static void applyAutomationParameterTarget(
        const AutomationParameterTarget &target,
        float value);
    void publishAutomationSnapshotLocked();
    void drainRetiredAutomationSnapshotsLocked();
    void attachRowBusNodes(RowState &r,
                           juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync);
    void ensureRowBusNodesAttached(int rowIndex,
                                   juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync,
                                   bool callerHoldsGraphLock = false);
    void retargetRowMeterTapPointers();
    void rebuildRowIdIndexCache();
    void publishMeterReadoutSnapshotLocked();
    juce::AudioProcessorGraph::Node::Ptr getRowInputNodeById(int rowId);
    int getRowIndexById(int rowId) const;
    void applyTrackEffectAutomationAtTimeSeconds(double timeSeconds);
    void resetTrackEffectAutomationLatches();
    void resetTrackEffectAutomationLatchesForRow(int row);
    void addClipToRowIndex(int rowId, int clipId);
    void removeClipFromRowIndex(int rowId, int clipId);
    long long routedClipBucketForTime(double timeSec) const noexcept;
    double routedClipScheduleEndSec(const ClipState &clip) const noexcept;
    bool routedClipMayRenderBlock(const RoutedClipRenderItem &item,
                                  double blockStartSec,
                                  double blockEndSec) const noexcept;
    void beginRoutedClipScheduleMutationLocked() noexcept;
    void endRoutedClipScheduleMutationLocked();
    void requestRoutedClipSchedulePublishLocked();
    void publishRoutedClipSchedulesLocked();
    void refreshRowRoutedSchedulePointersLocked();
    void drainRetiredRoutedClipScheduleSnapshotsLocked();
    void clearRoutedClipSchedules();
    void addClipToRoutedSchedule(const ClipState &clip);
    void removeClipFromRoutedSchedule(int rowId, int clipId);
    std::shared_ptr<juce::AudioProcessor> liveProcessorSharedForClip(const ClipState &clip) const noexcept;
    juce::AudioProcessor *liveProcessorForClip(ClipState &clip) noexcept;
    const juce::AudioProcessor *liveProcessorForClip(const ClipState &clip) const noexcept;
    TimelineClipProcessorBase *timelineProcessorForClip(ClipState &clip) noexcept;
    void prepareLiveClipProcessor(juce::AudioProcessor &processor);
    void releaseLiveClipProcessor(juce::AudioProcessor &processor);
    void retireLiveClipProcessorLocked(std::shared_ptr<juce::AudioProcessor> processor);
    void drainRetiredLiveClipProcessorsLocked();
    std::shared_ptr<juce::AudioProcessor> clearClipGraphNodes(
        int clipId,
        juce::AudioProcessorGraph::UpdateKind updateKind);
    void compactRowFxChain(int row);
    void compactMasterFxChain();
    bool isGraphConnectionPresent(juce::AudioProcessorGraph::NodeID src,
                                  juce::AudioProcessorGraph::NodeID dst,
                                  int ch) const;
    void ensureMasterOutputRouting();
    bool applyPreferredAudioDeviceSetup(int desiredInputChannels,
                                        bool forceReopen,
                                        const juce::String &reason,
                                        double requestedSampleRate = 0.0,
                                        int requestedBufferSize = 0);
    void refreshMidiInputCallbacks();
    void clearMidiInputCallbacks();
    void logCurrentAudioDeviceState(const juce::String &reason) const;
    void syncLiveInputMonitorRoutingLocked(
        juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync);
    void clearLiveInputMonitorConnectionsLocked(
        juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync);
};

class MetronomeAudioCallback : public juce::AudioIODeviceCallback
{
public:
    MetronomeAudioCallback(juce::AudioProcessorPlayer &p, JuceEngine &e)
        : player(p), engine(e)
    {
    }

    // ===== Public API =====
    void setEnabled(bool e) { enabled = e; }
    void setVolume(float v) { volume = v; } // 0..1
    void setBpm(double newBpm)
    {
        bpm = newBpm;
        updateMsPerBeat();
    }

    void setTimeSignature(int numerator, int denominator)
    {
        beatsPerBar = juce::jlimit(1, 12, numerator);
        beatUnit = (denominator == 2 || denominator == 4 ||
                    denominator == 8 || denominator == 16)
                       ? denominator
                       : 4;
        updateMsPerBeat();
        alignToTransport();
    }

    void setTransportMs(double ms)
    {
        transportMs = ms;
        alignToTransport();
    }

    void setIsPlaying(bool p) { isPlaying = p; }

    void beginFirstValidCallbackProof() noexcept
    {
        firstValidCallbackCompleted.store(false, std::memory_order_release);
        firstValidCallbackCount.store(0, std::memory_order_relaxed);
        firstValidCallbackFrames.store(0, std::memory_order_relaxed);
        firstValidCallbackSampleRate.store(0.0, std::memory_order_relaxed);
        firstValidCallbackRequested.store(true, std::memory_order_release);
        firstValidCallback.reset();
    }

    bool waitForFirstValidCallback(int timeoutMilliseconds) noexcept
    {
        const double deadlineMs = juce::Time::getMillisecondCounterHiRes() +
            juce::jmax(0, timeoutMilliseconds);
        while (firstValidCallbackRequested.load(std::memory_order_acquire))
        {
            if (hasCompletedFirstValidCallback())
            {
                firstValidCallbackRequested.store(
                    false, std::memory_order_release);
                return true;
            }

            const int remainingMs = static_cast<int>(juce::jmax(
                0.0, deadlineMs - juce::Time::getMillisecondCounterHiRes()));
            if (remainingMs <= 0 || !firstValidCallback.wait(remainingMs))
                break;
        }

        firstValidCallbackRequested.store(false, std::memory_order_release);
        return false;
    }

    void cancelFirstValidCallbackProofWait() noexcept
    {
        firstValidCallbackRequested.store(false, std::memory_order_release);
        firstValidCallbackCompleted.store(false, std::memory_order_release);
        firstValidCallbackFrames.store(0, std::memory_order_relaxed);
        firstValidCallbackSampleRate.store(0.0, std::memory_order_relaxed);
        firstValidCallback.signal();
    }

    bool hasCompletedFirstValidCallback() const noexcept
    {
        return callbackReady.load(std::memory_order_acquire) &&
            firstValidCallbackCompleted.load(std::memory_order_acquire);
    }

    std::uint64_t getFirstValidCallbackCount() const noexcept
    {
        return firstValidCallbackCount.load(std::memory_order_acquire);
    }

    int getFirstValidCallbackFrames() const noexcept
    {
        return firstValidCallbackFrames.load(std::memory_order_acquire);
    }

    double getFirstValidCallbackSampleRate() const noexcept
    {
        return firstValidCallbackSampleRate.load(std::memory_order_acquire);
    }

    // ===== AudioIODeviceCallback =====
    void audioDeviceAboutToStart(juce::AudioIODevice *device) override
    {
        engine.advanceInputMonitorStreamGenerationV2();
        callbackReady.store(false, std::memory_order_release);
        sampleRate = device->getCurrentSampleRate();
        const int preparedBlockCapacity = device->getCurrentBufferSizeSamples();
        const int preparedInputChannels =
            device->getActiveInputChannels().countNumberOfSetBits();
        const int preparedOutputChannels =
            device->getActiveOutputChannels().countNumberOfSetBits();
        updateMsPerBeat();
        clickPhaseInc = juce::MathConstants<double>::twoPi * clickFrequency / sampleRate;
        engine.beginAudioDeviceClockV2(sampleRate);
        engine.setBlockPlayingState(false);
        player.audioDeviceAboutToStart(device);
        engine.prepareLiveClipProcessorsForCurrentDevice();
        engine.completeGraphClockV2(sampleRate, preparedBlockCapacity);
        alignToTransport();
        expectedBlockCapacity.store(preparedBlockCapacity, std::memory_order_relaxed);
        expectedInputChannels.store(preparedInputChannels, std::memory_order_relaxed);
        expectedOutputChannels.store(preparedOutputChannels, std::memory_order_relaxed);
        callbackReady.store(
            preparedBlockCapacity > 0 && preparedOutputChannels > 0,
            std::memory_order_release);
    }

    void audioDeviceStopped() override
    {
        engine.advanceInputMonitorStreamGenerationV2();
        callbackReady.store(false, std::memory_order_release);
        firstValidCallbackCompleted.store(false, std::memory_order_release);
        firstValidCallbackFrames.store(0, std::memory_order_relaxed);
        firstValidCallbackSampleRate.store(0.0, std::memory_order_relaxed);
        expectedBlockCapacity.store(0, std::memory_order_relaxed);
        expectedInputChannels.store(0, std::memory_order_relaxed);
        expectedOutputChannels.store(0, std::memory_order_relaxed);
        // CoreAudio may stop and restart an owned device while a Bluetooth
        // profile settles. Keep an active proof armed for the restarted
        // callback; explicit cancellation or its bounded deadline ends it.
        firstValidCallback.signal();
        player.audioDeviceStopped();
    }

    void audioDeviceIOCallbackWithContext(
        const float *const *inputChannelData,
        int numInputChannels,
        float *const *outputChannelData,
        int numOutputChannels,
        int numSamples,
        const juce::AudioIODeviceCallbackContext &context) override
    {
        const bool ready = callbackReady.load(std::memory_order_acquire);
        const int knownBlockCapacity =
            expectedBlockCapacity.load(std::memory_order_relaxed);
        const int knownInputs =
            expectedInputChannels.load(std::memory_order_relaxed);
        const int knownOutputs =
            expectedOutputChannels.load(std::memory_order_relaxed);
        const bool unexpectedCallbackShape =
            !ready ||
            numSamples <= 0 ||
            (numInputChannels > 0 && inputChannelData == nullptr) ||
            (numOutputChannels > 0 && outputChannelData == nullptr) ||
            numSamples > knownBlockCapacity ||
            numInputChannels != knownInputs ||
            numOutputChannels != knownOutputs;

        if (unexpectedCallbackShape)
        {
            if (outputChannelData != nullptr && numSamples > 0)
            {
                for (int ch = 0; ch < numOutputChannels; ++ch)
                {
                    if (outputChannelData[ch] != nullptr)
                        juce::FloatVectorOperations::clear(outputChannelData[ch], numSamples);
                }
            }

            if (!engine.isV2PlaybackSession())
                engine.requestAudioDeviceRefreshAsync("unexpected-callback-shape");
            return;
        }

        const auto callbackStartTicks = juce::Time::getHighResolutionTicks();

        engine.captureInput(inputChannelData, numInputChannels, numSamples);

        // ===============================
        // 2️⃣ CLEAR OUTPUT
        // ===============================
        for (int ch = 0; ch < numOutputChannels; ++ch)
        {
            if (outputChannelData[ch] != nullptr)
                juce::FloatVectorOperations::clear(outputChannelData[ch], numSamples);
        }

        const bool blockWasPlaying = engine.isTransportPlaying();
        engine.setBlockPlayingState(blockWasPlaying);
        engine.wrapPlayingTransportToLoopIfNeeded();
        transportMs = engine.getTransportSeconds() * 1000.0;
        alignToTransport();
        engine.dispatchQueuedLiveMidiInputEventsForAudioThread();

        // ===============================
        // 3️⃣ RENDER GRAPH
        // ===============================
#if JUCE_IOS
        const bool routeVerifiedInput =
            engine.shouldRouteLiveInputToGraphV2();
#else
        constexpr bool routeVerifiedInput = false;
#endif
        auto renderGraphChunk = [&](int startSample, int count)
        {
            if (count <= 0)
                return;
            const float *inputPtrs[32];
            float *outputPtrs[32];
            const float *const *inputData = nullptr;
            int inputCount = 0;
            if (routeVerifiedInput && inputChannelData != nullptr)
            {
                inputCount = juce::jmin(numInputChannels, 32);
                for (int ch = 0; ch < inputCount; ++ch)
                    inputPtrs[ch] = inputChannelData[ch] != nullptr
                                        ? inputChannelData[ch] + startSample
                                        : nullptr;
                inputData = inputPtrs;
            }
            const int outputCount = juce::jmin(numOutputChannels, 32);
            for (int ch = 0; ch < outputCount; ++ch)
                outputPtrs[ch] = outputChannelData[ch] != nullptr
                                     ? outputChannelData[ch] + startSample
                                     : nullptr;
            engine.setBlockTransportStartFromCurrent();
            engine.beginRealtimeAudioRenderBlock();
            engine.applyTrackEffectAutomationAtCurrentBlockStart();
            player.audioDeviceIOCallbackWithContext(
                inputData,
                inputCount,
                outputPtrs,
                outputCount,
                count,
                context);
            engine.advanceTransportBySamples(count);
        };
        if (blockWasPlaying && engine.isLoopRegionActive() && numSamples > 0)
        {
            int offset = 0;
            while (offset < numSamples)
            {
                engine.wrapPlayingTransportToLoopIfNeeded();
                int chunk = numSamples - offset;
                const int untilWrap = engine.samplesUntilLoopWrap(sampleRate);
                if (untilWrap > 0)
                    chunk = juce::jmin(chunk, untilWrap);
                renderGraphChunk(offset, chunk);
                offset += chunk;
            }
        }
        else
        {
            engine.setBlockTransportStartFromCurrent();
            engine.beginRealtimeAudioRenderBlock();
            engine.applyTrackEffectAutomationAtCurrentBlockStart();
            player.audioDeviceIOCallbackWithContext(
                routeVerifiedInput ? inputChannelData : nullptr,
                routeVerifiedInput ? numInputChannels : 0,
                outputChannelData,
                numOutputChannels,
                numSamples,
                context);
            engine.advanceTransportBySamples(numSamples);
        }

        if (!enabled || !isPlaying)
        {
            engine.updateMasterMeterFromOutput(outputChannelData, numOutputChannels, numSamples);
            engine.recordRealtimeAudioCallback(
                numSamples,
                sampleRate,
                juce::Time::getHighResolutionTicks() - callbackStartTicks);
            completeFirstValidCallbackProof(numSamples);
            return;
        }

        const double msPerSample = 1000.0 / sampleRate;

        for (int i = 0; i < numSamples; ++i)
        {
            transportMs += msPerSample;
            if (engine.isLoopRegionActive())
            {
                const double wrappedMs =
                    engine.wrapTransportSecondsToLoop(transportMs * 0.001) *
                    1000.0;
                if (wrappedMs + 1.0e-6 < transportMs)
                {
                    transportMs = wrappedMs;
                    alignToTransport();
                }
            }

            if (transportMs >= nextBeatMs)
            {
                currentBeat = (currentBeat + 1) % beatsPerBar;
                clickPhase = 0;
                clickPhaseRad = 0.0;
                nextBeatMs += msPerBeat;

                const bool accent = (currentBeat == 0);
                setupClickFilter(accent);
                setupTone(accent);
            }

            float clickSample = 0.0f;
            float toneSample = 0.0f;

            // ===== Click transient =====
            if (clickPhase < clickLength)
            {
                const double impulse = (clickPhase == 0) ? 1.0 : 0.0;

                const double y =
                    a0 * impulse +
                    a1 * z1 +
                    a2 * z2 -
                    b1 * z1 -
                    b2 * z2;

                z2 = z1;
                z1 = y;

                clickSample = (float)(y * clickEnv * volume);
                clickEnv *= (1.0 - clickEnvDecay);

                ++clickPhase;
            }

            // ===== Tonal body =====
            if (toneEnv > 0.0001)
            {
                toneSample =
                    (float)(std::sin(tonePhase) *
                            toneEnv *
                            volume *
                            0.35f);

                tonePhase += tonePhaseInc;
                toneEnv *= (1.0 - toneEnvDecay);
            }

            // ===== Mix =====
            const float out = clickSample + toneSample;

            for (int ch = 0; ch < numOutputChannels; ++ch)
                outputChannelData[ch][i] += out;
        }

        engine.updateMasterMeterFromOutput(outputChannelData, numOutputChannels, numSamples);
        engine.recordRealtimeAudioCallback(
            numSamples,
            sampleRate,
            juce::Time::getHighResolutionTicks() - callbackStartTicks);
        completeFirstValidCallbackProof(numSamples);
    }

    void setupClickFilter(bool accent)
    {
        const double freq = accent ? 6800.0 : 5200.0;
        const double q = accent ? 1.3 : 1.0;

        const double w0 = juce::MathConstants<double>::twoPi * freq / sampleRate;
        const double alpha = std::sin(w0) / (2.0 * q);
        const double cosw = std::cos(w0);

        const double b0 = alpha;
        const double b1n = 0.0;
        const double b2n = -alpha;
        const double a0n = 1.0 + alpha;
        const double a1n = -2.0 * cosw;
        const double a2n = 1.0 - alpha;

        a0 = b0 / a0n;
        a1 = b1n / a0n;
        a2 = b2n / a0n;
        b1 = a1n / a0n;
        b2 = a2n / a0n;

        z1 = z2 = 0.0;

        clickEnv = 1.0;
        clickEnvDecay = accent ? 0.004 : 0.006;
    }

    void setupTone(bool accent)
    {
        const double freq = accent ? 2400.0 : 1800.0; // musical, not harsh
        tonePhaseInc =
            juce::MathConstants<double>::twoPi * freq / sampleRate;

        tonePhase = 0.0;
        toneEnv = 1.0;
        toneEnvDecay = accent ? 0.0025 : 0.0035;
    }

private:
    void completeFirstValidCallbackProof(int numSamples) noexcept
    {
        if (!firstValidCallbackRequested.load(std::memory_order_acquire))
            return;
        firstValidCallbackFrames.store(numSamples, std::memory_order_release);
        firstValidCallbackSampleRate.store(sampleRate, std::memory_order_release);
        firstValidCallbackCount.fetch_add(1, std::memory_order_relaxed);
        firstValidCallbackCompleted.store(true, std::memory_order_release);
        firstValidCallback.signal();
    }

    juce::AudioProcessorPlayer &player;
    JuceEngine &engine;
    std::atomic<bool> callbackReady{false};
    std::atomic<int> expectedBlockCapacity{0};
    std::atomic<int> expectedInputChannels{0};
    std::atomic<int> expectedOutputChannels{0};
    std::atomic<bool> firstValidCallbackRequested{false};
    std::atomic<bool> firstValidCallbackCompleted{false};
    std::atomic<std::uint64_t> firstValidCallbackCount{0};
    std::atomic<int> firstValidCallbackFrames{0};
    std::atomic<double> firstValidCallbackSampleRate{0.0};
    juce::WaitableEvent firstValidCallback;

    bool enabled = false;
    bool isPlaying = false;

    float volume = 0.5f;
    double bpm = 120.0;
    int beatsPerBar = 4;
    int beatUnit = 4;

    double sampleRate = 44100.0;
    double msPerBeat = 500.0;
    double transportMs = 0.0;
    double nextBeatMs = 0.0;

    int currentBeat = 0;
    int clickPhase = 0;

    double clickFrequency = 8000.0; // FL-style brightness
    double clickPhaseRad = 0.0;
    double clickPhaseInc = 0.0;

    const int clickLength = 130;    // ~0.9 ms @ 44.1k
    const float clickDecay = 0.15f; // very fast decay

    double clickEnv = 0.0;
    double clickEnvDecay = 0.0;

    double tonePhase = 0.0;
    double tonePhaseInc = 0.0;
    double toneEnv = 0.0;
    double toneEnvDecay = 0.0;

    juce::Random rng;

    // One-pole bandpass approximation
    double bp_z1 = 0.0;
    double bp_z2 = 0.0;
    double bp_a0 = 0.0;
    double bp_a1 = 0.0;
    double bp_b1 = 0.0;
    double bp_b2 = 0.0;

    double env = 0.0;
    double envDecay = 0.0;

    double z1 = 0.0;
    double z2 = 0.0;

    // biquad coefficients
    double a0 = 0.0;
    double a1 = 0.0;
    double a2 = 0.0;
    double b1 = 0.0;
    double b2 = 0.0;

    void updateMsPerBeat()
    {
        msPerBeat = (60000.0 / juce::jmax(1.0, bpm)) *
                    4.0 / juce::jmax(1, beatUnit);
    }

    void alignToTransport()
    {
        const double beatIndex = transportMs / msPerBeat;
        currentBeat = (int)std::floor(beatIndex) % beatsPerBar;
        nextBeatMs = (std::floor(beatIndex) + 1.0) * msPerBeat;
    }
};

class IOSBluetoothDuplexProbeCallback final
    : public juce::AudioIODeviceCallback
{
public:
    void audioDeviceAboutToStart(juce::AudioIODevice *device) override
    {
        ready.store(false, std::memory_order_release);
        callbackCount.store(0, std::memory_order_relaxed);
        firstValidCallback.reset();
        if (device == nullptr)
            return;

        const int blockCapacity = device->getCurrentBufferSizeSamples();
        const int inputChannels =
            device->getActiveInputChannels().countNumberOfSetBits();
        const int outputChannels =
            device->getActiveOutputChannels().countNumberOfSetBits();
        expectedBlockCapacity.store(blockCapacity, std::memory_order_relaxed);
        expectedInputChannels.store(inputChannels, std::memory_order_relaxed);
        expectedOutputChannels.store(outputChannels, std::memory_order_relaxed);
        ready.store(
            device->getCurrentSampleRate() > 1000.0 &&
                blockCapacity > 0 && inputChannels == 1 &&
                outputChannels > 0,
            std::memory_order_release);
    }

    void audioDeviceStopped() override
    {
        ready.store(false, std::memory_order_release);
        expectedBlockCapacity.store(0, std::memory_order_relaxed);
        expectedInputChannels.store(0, std::memory_order_relaxed);
        expectedOutputChannels.store(0, std::memory_order_relaxed);
        firstValidCallback.signal();
    }

    void audioDeviceIOCallbackWithContext(
        const float *const *inputChannelData,
        int numInputChannels,
        float *const *outputChannelData,
        int numOutputChannels,
        int numSamples,
        const juce::AudioIODeviceCallbackContext &) override
    {
        if (outputChannelData != nullptr && numSamples > 0)
        {
            for (int ch = 0; ch < numOutputChannels; ++ch)
                if (outputChannelData[ch] != nullptr)
                    juce::FloatVectorOperations::clear(
                        outputChannelData[ch], numSamples);
        }

        bool pointersValid = inputChannelData != nullptr &&
            outputChannelData != nullptr;
        for (int ch = 0; pointersValid && ch < numInputChannels; ++ch)
            pointersValid = inputChannelData[ch] != nullptr;
        for (int ch = 0; pointersValid && ch < numOutputChannels; ++ch)
            pointersValid = outputChannelData[ch] != nullptr;

        const bool valid = ready.load(std::memory_order_acquire) &&
            numSamples > 0 &&
            numSamples <= expectedBlockCapacity.load(
                std::memory_order_relaxed) &&
            numInputChannels == expectedInputChannels.load(
                std::memory_order_relaxed) &&
            numOutputChannels == expectedOutputChannels.load(
                std::memory_order_relaxed) &&
            pointersValid;
        if (valid)
        {
            callbackCount.fetch_add(1, std::memory_order_relaxed);
            firstValidCallback.signal();
        }
    }

    bool isReady() const noexcept
    {
        return ready.load(std::memory_order_acquire);
    }

    bool hasCompletedValidCallback() const noexcept
    {
        return isReady() &&
            callbackCount.load(std::memory_order_acquire) > 0;
    }

    bool waitForFirstValidCallback(int timeoutMilliseconds) noexcept
    {
        if (hasCompletedValidCallback())
            return true;
        return firstValidCallback.wait(timeoutMilliseconds) &&
            hasCompletedValidCallback();
    }

    std::uint64_t getCallbackCount() const noexcept
    {
        return callbackCount.load(std::memory_order_acquire);
    }

private:
    std::atomic<bool> ready{false};
    std::atomic<int> expectedBlockCapacity{0};
    std::atomic<int> expectedInputChannels{0};
    std::atomic<int> expectedOutputChannels{0};
    std::atomic<std::uint64_t> callbackCount{0};
    juce::WaitableEvent firstValidCallback;
};
