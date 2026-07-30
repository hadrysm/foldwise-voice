# Guided-setup ordering patterns in macOS dictation apps

Research for [issue #328](https://github.com/hadrysm/foldwise-voice/issues/328),
current as of 2026-07-26. Sources are first-party documentation or official
source repositories. “Exact” below means the source explicitly describes or
implements the sequence; otherwise the limitation is called out.

## Conclusion

There is no industry-standard order. The clearest shared pattern is:

1. Resolve prerequisites before asking the user to practice.
2. Put shortcut setup near a real first Dictation so it can be verified.
3. Treat AI rewriting/polishing as an optional layer after plain transcription
   works.

FoldWise should use:

1. **Accessibility**
2. **Speech model** — start the download, then keep it running in the background
3. **Microphone** — grant access and verify live input
4. **Push-to-Talk shortcut** — configure it and perform a real first Dictation
5. **Polish (optional)**

This is not the most common competitor order: the two products with the most
explicit permission sequences put Microphone before Accessibility. It is still
a coherent FoldWise-specific choice. Accessibility is the most disruptive
System Settings handoff and enables the system-wide insertion/shortcut
experience; resolving it first gets the largest trust and setup hurdle out of
the way. Starting the model next is a latency optimization: microphone and
shortcut setup can hide part of the download time.

Do not label **Dictation ready** until the model is ready. The map deliberately
keeps that capability state independent from **Setup completed**, and the
dedicated speech-model ticket owns whether Guided setup may reach its terminal
outcome while the download continues.

## Documented product sequences

| Product | Documented order | Evidence quality |
| --- | --- | --- |
| **Wispr Flow** | Microphone permission → Accessibility permission → microphone test → shortcut → languages → “Try It Yourself” Dictation demos | **Exact.** The [official Mac setup guide](https://docs.wisprflow.ai/articles/3152211871-setup-guide) names both the permission suborder and tutorial steps. Flow is cloud-based, so there is no local speech-model download step. |
| **VoiceInk** | Permissions (**Microphone → Accessibility**, with Screen Recording optional) → choose microphone → configure local/cloud transcription model → optional AI/API setup → experience, beginning with shortcut setup and a simple Dictation | **Exact in current official source.** The stage and permission order are defined in [`OnboardingPermissionModels.swift`](https://github.com/Beingpax/VoiceInk/blob/ec610325b8d3fd760eef93d3b24435bbb3e2139b/VoiceInk/Views/Onboarding/OnboardingPermissionModels.swift#L3-L115); [`OnboardingFlowController.swift`](https://github.com/Beingpax/VoiceInk/blob/ec610325b8d3fd760eef93d3b24435bbb3e2139b/VoiceInk/Views/Onboarding/OnboardingFlowController.swift#L11-L55) gates microphone selection behind permissions and model setup behind microphone selection. The first experience is a [simple Dictation using the configured model](https://github.com/Beingpax/VoiceInk/blob/ec610325b8d3fd760eef93d3b24435bbb3e2139b/VoiceInk/Views/Onboarding/OnboardingExperienceModels.swift#L146-L177), followed by enhancement. |
| **Superwhisper** | Permissions → language → cloud/local AI model → microphone/audio → guided first Dictation with keyboard shortcuts → verification | **Listed, not guaranteed screen-by-screen.** The official [Initial Setup](https://superwhisper.com/docs/get-started/introduction#initial-setup) section presents this order as bullets rather than numbered screens. Its [data-flow documentation](https://superwhisper.com/docs/security/sensitive-data#how-your-data-flows) distinguishes transcription from optional language-model post-processing. |
| **MacWhisper** | No complete first-run sequence is publicly documented. Dictation shortcut setup, installed speech models, and optional AI cleanup are separate configuration surfaces. | **Do not infer an order.** The official docs separately cover [Dictation setup](https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature), [global shortcuts](https://docs.macwhisper.com/article/16-global), and [installed models](https://docs.macwhisper.com/article/57-macwhisper-command-line-tool#3-working-with-models). |
| **Apple Voice Control / Dictation** | Voice Control: Accessibility settings → turn on → one-time file download → ready. Standard Dictation exposes enablement, languages, microphone, and shortcut as peer settings rather than a wizard. | **Exact for Voice Control.** Apple says first enablement performs a [one-time file download and indicates readiness only after it completes](https://support.apple.com/guide/mac-help/turn-voice-control-on-or-off-mchl63d14732/mac). Apple’s [Dictation settings](https://support.apple.com/guide/mac-help/keyboard-settings-kbdm162/mac) do not define a step order. Voice Control’s location under Accessibility is not evidence that a third-party app should request Accessibility TCC permission first. |

## Why the orders differ

The documented sequences optimize for different things:

- **Microphone first** gives immediate, understandable feedback: the app asks to
  hear the user, then can show a live level test. This is the explicit Wispr
  Flow and VoiceInk pattern.
- **Accessibility first** front-loads the harder trust and System Settings
  handoff. For FoldWise this is defensible because system-wide insertion and
  global control are part of the core promise, but the screen must explain that
  benefit before opening Settings.
- **Model early** hides download latency. Apple Voice Control makes download
  part of enablement; Superwhisper lists model choice before microphone setup.
  FoldWise can start the download on step 2 and let it continue through steps 3
  and 4.
- **Shortcut late** lets the user immediately use what they configured. Wispr
  Flow follows shortcut setup with a Dictation demo, and VoiceInk embeds
  shortcut setup in its first Dictation experience.
- **Polish last** preserves a clean dependency story: recording and
  transcription prove the core product first; an optional text transform comes
  afterward. VoiceInk demonstrates simple Dictation before enhancement, and
  Superwhisper documents language-model post-processing as optional.

Apple’s Human Interface Guidelines reinforce the framing, not a particular
sequence: request access only when the need is clear, explain the precise
benefit, and postpone nonessential customization
([Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy/),
[Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)).

## Recommendation for the ordering decision

Adopt the proposed FoldWise order. On the Speech model step, “Continue” should
mean “download started,” not “model ready,” so the download can overlap the
Microphone and shortcut steps. The shortcut step may offer a real Dictation
when the model is ready, but its completion cannot depend on model readiness
without overturning the map's settled rule that Microphone is the only hard
gate. Offer Polish last, and make declining it an ordinary completion path.
