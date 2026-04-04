(function () {
  const translations = {
    en: {
      meta: {
        home_title: "Mixroom",
        home_description:
          "AI isn't the artist. And it never should be. Mixroom doesn't create for you. It executes your intent.",
        subscribe_title: "Mixroom | Sign up",
        subscribe_description:
          "Beta drops April 3rd. Mixroom doesn't create for you. It executes your intent.",
        terms_title: "Mixroom | Terms",
        privacy_title: "Mixroom | Privacy",
        delete_title: "Mixroom | Delete Account",
        subprocessors_title: "Mixroom | Subprocessors",
      },
      nav: {
        home: "Home",
        signup: "Sign up",
        terms: "Terms",
        privacy: "Privacy",
        delete: "Delete Account",
        subprocessors: "Subprocessors",
      },
      common: {
        beta: "Beta drops April 3rd.",
        form_name: "Name",
        form_email: "Email*",
        form_newsletter: "Yes, subscribe me to your newsletter.*",
        company: "Mixroom Co., Ltd.",
        address: "135, Jungdae-ro, Songpa-gu, Seoul, S.KOREA",
        copyright: "© 2025 Mixroom. All rights reserved.",
      },
      faq: {
        eyebrow: "Questions people ask before they try Mixroom.",
        title: "Common Questions",
        body:
          "The important parts: what Mixroom is, what it is not, and how control, ownership, and workflow actually work.",
        items: [
          {
            q: "What is a DAW?",
            a: [
              "DAW stands for Digital Audio Workstation.",
              "It is the software used to create, record, edit, and produce music.",
            ],
          },
          {
            q: "What is Mixroom?",
            a: [
              "Mixroom is a next generation DAW with a built-in AI co-producer.",
              "You tell it where you want the music to go, and it helps execute that direction.",
              "It does not replace your role in the process. It works with you as a production partner, not a music generator.",
            ],
          },
          {
            q: "How is this different from AI music generators?",
            a: [
              "Mixroom does not generate music.",
              "Most AI music tools produce a finished result for you. Mixroom takes a different approach: it helps you finish your music.",
              "You bring the idea, the taste, and the direction. Mixroom helps execute it.",
              "That means you can change course, refine details, stop midway, and keep shaping the track as you go. The process stays in your hands.",
            ],
          },
          {
            q: "Can I use Mixroom without music theory or production experience?",
            a: [
              "Yes.",
              "You do not need music theory, technical production knowledge, or a deep understanding of plugins and mixing tools to get started.",
              "If you can describe a mood, a feeling, or the kind of sound you want, that is enough.",
              "Mixroom helps translate creative intent into action, so you can focus less on engineering terminology and more on the music you want to make.",
              "And as you grow, you can still go deeper. Mixroom lowers the barrier. It does not limit you.",
              "If you have music in your head but no clear way to bring it out, Mixroom is built for you.",
            ],
          },
          {
            q: "Will AI make changes on its own or do things I do not understand?",
            a: [
              "No.",
              "Mixroom is not a black box. It works through an execution-based workflow that stays visible to you.",
              "You give direction. Mixroom applies the change. You review it. Then you can keep it, adjust it yourself, or undo it.",
              "That means edits are not hidden behind vague AI output. You can see what changed, whether that is the edit itself, parameter movement, or plugin adjustments, and stay in control of the process.",
              "Nothing is silently decided for you.",
            ],
          },
          {
            q: "Will everything sound the same if AI is involved?",
            a: [
              "No.",
              "Generative AI tends to produce similar results because it is built around pattern-based output. Mixroom works differently. It responds to your intent.",
              "The outcome depends on your decisions, your taste, and your direction. Same tool. Completely different results.",
              "Mixroom is not here to standardize music. It is here to help you realize your own sound.",
            ],
          },
          {
            q: "Will I lose the feeling of making it myself?",
            a: [
              "No.",
              "Mixroom does not take over the creative role. It removes repetitive work and lowers the technical burden, so you can focus more on decisions that actually shape the music.",
              "Less mechanical effort. More creative control. That is the shift.",
            ],
          },
          {
            q: "Who owns the copyright?",
            a: [
              "You do. 100%.",
              "Mixroom works on top of your music using a non-destructive editing workflow.",
              "It does not generate results by recombining outside material or claim authorship over the output.",
              "Your music stays yours. Mixroom does not claim ownership of your work.",
            ],
          },
          {
            q: "Is Mixroom mobile-only? Will there be a desktop version?",
            a: [
              "For now, Mixroom is available on mobile devices, including phones and tablets.",
              "A desktop version is on the way and is planned for later this year, enabling a more flexible multi-platform workflow.",
              "So today, you can start on mobile. Soon, you will be able to continue across desktop as well.",
            ],
          },
        ],
      },
      home: {
        hero_title: "AI isn't the artist.<span>And it never should be.</span>",
        hero_subhead: "Mixroom doesn't create for you. It executes your intent.",
        hero_body_1: "Tell Mixroom where you want the song to go.",
        hero_body_2: "It handles the technical work without taking the creative decision away from you.",
        hero_body_3: "No studio setup. No years of learning before you can begin.",
        hero_secondary_cta: "See the difference",
        hero_footnote: "Your decision. Never generated.",
        hero_note_top: "Traditional path<br /><span>Spend years learning. Spend thousands on gear.</span>",
        hero_note_bottom: "Generator tools<br /><span>Press a button. Get a track. But is it yours?</span>",
        story_eyebrow: "Making music still means choosing between two bad options.",
        story_intro: "Keep the idea.<br />Lose the friction.",
        story_intro_body:
          "If you make it yourself, the tooling gets in the way. If you let a generator do it, the result stops feeling like yours. Mixroom is built between those two extremes.",
        story_step_1_label: "Traditional path",
        story_left_title: "Spend years learning.<br />Spend thousands on gear.",
        story_left_body: "If you want full control, you still have to fight your way through tools, gear, and a steep learning curve.",
        story_left_caption: "By the time you can execute, the first idea is often gone.",
        story_step_2_label: "Generator path",
        story_right_title: "Press a button. Get a track.<br />But is it yours?",
        story_right_body: "It may be fast, but your taste and intent get flattened into output.",
        story_tag_1: "No identity.",
        story_tag_2: "No ownership.",
        question_eyebrow: "So the better question is:",
        story_step_3_label: "Mixroom",
        question_title:
          "What if you stayed in control -<br />and AI handled the execution?",
        story_step_3_body: "Not a substitute. Not a generator. A new layer between idea and execution.",
        product_eyebrow: "Meet Mixroom",
        product_title: "The first DAW with a personal AI co-producer.",
        product_body_1: "Not a substitute. Not a generator.",
        product_body_2: "A new layer between idea and execution.",
        product_body_3: "No prompting. Just musical conversation.",
        commandment_1: "You decide.",
        commandment_2: "AI executes.",
        product_principle_1_label: "Speed",
        product_principle_2_label: "Ownership",
        product_principle_3_label: "Workflow",
        product_strong_1: "Fast where it should be. Human where it matters.",
        product_strong_2: "If you made it, you own it.",
        product_strong_3: "No prompting. Just musical conversation.",
        final_eyebrow: "Create. Remix. Share.",
        final_title: "Build on each other.",
        final_body: "Mixroom is coming.",
      },
      subscribe: {
        title: "Mixroom doesn't create for you.<br />It executes your intent.",
        body_1: "You decide what you want. We make it real.",
        body_2: "Just your phone - and a conversation.",
      },
    },
    ko: {
      meta: {
        home_title: "Mixroom",
        home_description:
          "AI는 음악을 만들 수는 있어도, 뮤지션이 될 수는 없습니다. Mixroom은 대신 만들지 않습니다.",
        subscribe_title: "Mixroom | 가입",
        subscribe_description:
          "AI는 음악을 만들 수는 있어도, 뮤지션이 될 수는 없습니다. Mixroom은 대신 만들지 않습니다.",
        terms_title: "Mixroom | 이용약관",
        privacy_title: "Mixroom | 개인정보",
        delete_title: "Mixroom | 계정 삭제",
        subprocessors_title: "Mixroom | 서브프로세서",
      },
      nav: {
        home: "Home",
        signup: "Sign up",
        terms: "Terms",
        privacy: "Privacy",
        delete: "Delete Account",
        subprocessors: "Subprocessors",
      },
      common: {
        beta: "Beta drops April 3rd.",
        form_name: "Name",
        form_email: "Email*",
        form_newsletter: "Yes, subscribe me to your newsletter.*",
        company: "(주) 믹스룸",
        address: "135, Jungdae-ro, Songpa-gu, Seoul, S.KOREA",
        copyright: "© 2025 Mixroom. All rights reserved.",
      },
      faq: {
        eyebrow: "Mixroom을 쓰기 전에 가장 많이 듣는 질문들입니다.",
        title: "자주 묻는 질문",
        body:
          "Mixroom이 무엇인지, 무엇이 아닌지, 그리고 통제권과 저작권, 작업 방식이 실제로 어떻게 작동하는지 정리했습니다.",
        items: [
          {
            q: "DAW가 뭐예요?",
            a: [
              "Digital Audio Workstation의 약자입니다.",
              "음악을 만들고, 녹음하고, 편집하고, 다듬는 작업을 할 수 있는 소프트웨어입니다.",
            ],
          },
          {
            q: "Mixroom은 무슨 서비스인가요?",
            a: [
              "Mixroom은 AI Co-Producer 기반 음악 제작 DAW입니다.",
              "사용자가 원하는 방향을 말하면, Mixroom은 그 의도를 이해하고 실제 작업 과정에 반영합니다.",
              "결과물을 대신 만들어주는 도구가 아니라, 당신의 의도를 따라 함께 작업하는 음악 제작 파트너에 가깝습니다.",
            ],
          },
          {
            q: "AI 음악 생성 도구랑 뭐가 다른가요?",
            a: [
              "가장 큰 차이는 Mixroom은 음악을 생성하지 않는다는 점입니다.",
              "기존 생성형 AI 음악 서비스는 프롬프트를 바탕으로 새로운 결과물을 만들어내는 방식입니다.",
              "반면 Mixroom은 곡을 대신 만들어주는 서비스가 아닙니다.",
              "사용자가 직접 만들고 있는 음악, 혹은 이미 가지고 있는 아이디어와 작업물을 바탕으로 AI의 도움을 받아 더 다듬고, 더 완성도 높게 만들어가는 AI Co-Producer DAW입니다.",
              "즉, Mixroom은 음악을 대신 만들어주는 도구가 아니라, 내 음악을 끝까지 완성할 수 있도록 함께 작업하는 도구입니다.",
            ],
          },
          {
            q: "음악 이론이나 프로듀싱 경험이 없어도 Mixroom을 쓸 수 있나요?",
            a: [
              "네.",
              "시작하는 데 음악 이론이나 전문적인 프로듀싱 지식, 플러그인이나 믹싱 툴에 대한 깊은 이해가 꼭 필요하지는 않습니다.",
              "원하는 분위기나 느낌, 혹은 만들고 싶은 사운드를 설명할 수 있다면 그것으로 충분합니다.",
              "Mixroom은 그런 창작 의도를 실제 작업으로 이어지게 도와주기 때문에, 기술적인 용어나 엔지니어링 지식보다 내가 만들고 싶은 음악에 더 집중할 수 있습니다.",
              "그리고 익숙해질수록 더 깊이 있게 활용할 수도 있습니다. Mixroom은 진입장벽을 낮추지만, 가능성을 제한하지는 않습니다.",
              "머릿속에 음악은 있지만 그걸 꺼내는 방법이 막막했던 사람이라면, Mixroom은 바로 그런 사람을 위해 만들어졌습니다.",
            ],
          },
          {
            q: "AI가 중간에 알아서 바꾸거나, 내가 모르는 작업을 하진 않나요?",
            a: [
              "아닙니다.",
              "Mixroom은 결과만 보여주는 블랙박스형 AI가 아니라, 실제로 어떤 수정이 이루어졌는지 확인할 수 있는 실행형 구조로 작동합니다.",
              "예를 들어 AI가 작업을 수행하면, 편집 내용이나 플러그인 값 변화처럼 무엇이 어떻게 바뀌었는지 사용자가 직접 보고 확인할 수 있습니다.",
              "마음에 들지 않으면 그대로 둘 필요가 없습니다.",
              "사용자가 직접 다시 수정할 수도 있고, 되돌리기(Undo)로 이전 상태로 되돌릴 수도 있습니다.",
              "즉, Mixroom은 사용자를 대신해 불투명하게 결과를 만들어내는 것이 아니라, 사용자의 지시에 따라 실행하고, 그 실행 결과를 사용자에게 열어두는 구조입니다.",
            ],
          },
          {
            q: "AI가 도와주면 결과가 다 비슷해지는 거 아닌가요?",
            a: [
              "아닙니다.",
              "생성형 AI는 비슷한 데이터 패턴을 바탕으로 결과를 만들기 때문에 결과물이 유사해질 가능성이 있습니다.",
              "하지만 Mixroom은 사용자의 의도를 기반으로 작동합니다. 같은 도구를 쓰더라도, 누가 어떤 방향으로 판단하고 조정하느냐에 따라 결과는 달라집니다.",
              "Mixroom은 결과를 획일화하는 도구가 아니라 개인의 판단과 스타일을 더 잘 구현하도록 돕는 도구입니다.",
            ],
          },
          {
            q: "내가 직접 만드는 감각이 사라지는 거 아닌가요?",
            a: [
              "아닙니다.",
              "Mixroom은 창작을 대신하지 않습니다.",
              "대신 반복 작업과 기술적 부담을 줄여주어, 사용자가 더 중요한 결정에 집중할 수 있게 돕습니다.",
              "쉽게 말해, 손은 덜 쓰고, 판단은 더 많이 하게 되는 구조입니다.",
              "그래서 오히려 “내가 만들고 있다”는 감각은 줄어드는 것이 아니라, 더 선명해질 수 있습니다.",
            ],
          },
          {
            q: "저작권 문제는 없나요?",
            a: [
              "결과물의 권리는 100% 사용자에게 귀속됩니다.",
              "Mixroom은 사용자의 창작물을 기반으로 동작하며, 비파괴 편집 방식 위에서 사용자의 의도를 반영해 작업을 확장합니다.",
              "기존 데이터를 조합해 결과를 자동 생성하는 구조가 아니라 사용자가 주도하는 작업 과정 위에서 실행되는 도구입니다.",
              "그래서 결과물에 대한 권리는 사용자에게 있으며, Mixroom은 그 결과물에 대한 권리를 주장하지 않습니다.",
            ],
          },
          {
            q: "Mixroom은 모바일 전용인가요? 데스크톱 버전도 나오나요?",
            a: [
              "현재 Mixroom은 스마트폰과 태블릿을 포함한 모바일 기기에서 사용 가능합니다.",
              "데스크톱 버전도 준비 중이며, 올해 말 출시를 목표로 개발하고 있습니다.",
              "이를 통해 더 유연한 멀티플랫폼 작업 흐름을 지원할 예정입니다.",
            ],
          },
        ],
      },
      home: {
        hero_title: "AI는 음악을 만들 수는 있어도,<span>뮤지션이 될 수는 없습니다.</span>",
        hero_subhead: "Mixroom은 대신 만들지 않습니다.",
        hero_body_1: "원하는 프로듀싱 방향을 말하면,",
        hero_body_2: "Mixroom이 창작의 결정권은 그대로 둔 채 실제 작업을 실행합니다.",
        hero_body_3: "장비도, 스튜디오도, 복잡한 기술도 없이 바로 시작할 수 있습니다.",
        hero_secondary_cta: "차이 보기",
        hero_footnote: "생성이 아닌, 당신의 결정으로.",
        hero_note_top:
          "전통적인 방식<br /><span>직접 만들기 위해 수년을 배우고 수백만 원을 투자해야 합니다.</span>",
        hero_note_bottom:
          "생성형 툴<br /><span>버튼을 누르면 결과가 나옵니다. 하지만 그게 정말 당신의 음악인가요?</span>",
        story_eyebrow: "지금의 음악 제작은 여전히 두 가지 나쁜 선택지 사이의 문제입니다.",
        story_intro: "지금의 음악 제작 툴은<br />늘 둘 중 하나였습니다.",
        story_intro_body:
          "직접 만들려면 너무 오래 걸리고, 버튼 하나로 만들면 의도와 정체성이 흐려집니다. Mixroom은 그 두 극단 사이를 다시 설계합니다.",
        story_step_1_label: "전통적인 방식",
        story_left_title:
          "직접 만들기 위해<br />수년을 배우고 수백만 원을 투자해야 합니다.",
        story_left_body: "직접 만들고 싶다면 여전히 툴과 장비, 긴 학습 곡선을 먼저 통과해야 합니다.",
        story_left_caption: "막상 실행할 수 있을 때쯤엔 처음의 아이디어가 흐려집니다.",
        story_step_2_label: "생성형 툴",
        story_right_title:
          "버튼을 누르면 결과가 나옵니다.<br />하지만 그게 정말 당신의 음악인가요?",
        story_right_body: "빠를 수는 있지만, 당신의 의도와 취향은 결과물 뒤로 밀려납니다.",
        story_tag_1: "정체성도",
        story_tag_2: "저작권도 불분명합니다.",
        question_eyebrow: "그래서 진짜 질문은 이것입니다.",
        story_step_3_label: "Mixroom",
        question_title:
          "\"창작은 그대로 두고,<br />작업만 AI 가 대신할 수는 없을까?\"",
        story_step_3_body: "대신 만드는 것도, 결과만 생성하는 것도 아닙니다. 의도와 실행 사이에 새로운 레이어를 둡니다.",
        product_eyebrow: "Mixroom",
        product_title: "당신의 의도를 실행하는 AI Co-Producer DAW",
        product_body_1: "당신이 만든 것은,",
        product_body_2: "당신의 것입니다.",
        product_body_3: "프롬프트가 아닌, '음악적 대화'로 작업해보세요.",
        commandment_1: "더 빠르게.",
        commandment_2: "더 완성도 높게.",
        product_principle_1_label: "속도",
        product_principle_2_label: "소유권",
        product_principle_3_label: "워크플로우",
        product_strong_1: "창작의 주도권은 그대로.",
        product_strong_2: "당신이 만든 것은, 당신의 것입니다.",
        product_strong_3: "프롬프트가 아닌, '음악적 대화'로 작업해보세요.",
        final_eyebrow: "만들고, 다듬고, 공유하는",
        final_title: "모든 과정 -",
        final_body: "곧 Mixroom에서 시작됩니다.",
      },
      subscribe: {
        title: "Mixroom은 대신 만들지 않습니다.<br />당신의 의도를 실제 작업으로 실행합니다.",
        body_1: "원하는 프로듀싱 방향을 말하면,",
        body_2: "Mixroom이 그 의도를 실제 작업으로 실행합니다.",
      },
    },
  };

  const langButtons = document.querySelectorAll("[data-lang-switch]");
  const langStorageKey = "mixroom_public_site_lang";
  const faqList = document.querySelector("[data-faq-list]");
  const path = window.location.pathname;
  const pageId = path === "/"
    ? "home"
    : path.startsWith("/subscribe")
      ? "subscribe"
      : path.startsWith("/terms")
        ? "terms"
        : path.startsWith("/privacy")
          ? "privacy"
          : path.startsWith("/delete-account")
            ? "delete"
            : path.startsWith("/subprocessors")
              ? "subprocessors"
              : "home";

  const resolveInitialLanguage = () => {
    const query = new URLSearchParams(window.location.search).get("lang");
    if (query === "ko" || query === "en") return query;
    const stored = window.localStorage.getItem(langStorageKey);
    return stored === "ko" ? "ko" : "en";
  };

  const applyLanguage = (lang) => {
    const active = translations[lang] || translations.en;
    const meta = active.meta || {};
    const resolveKey = (key) =>
      key.split(".").reduce((value, part) => {
        if (value && typeof value === "object") {
          return value[part];
        }
        return undefined;
      }, active);

    document.documentElement.lang = lang;

    const titleMap = {
      home: meta.home_title,
      subscribe: meta.subscribe_title,
      terms: meta.terms_title,
      privacy: meta.privacy_title,
      delete: meta.delete_title,
      subprocessors: meta.subprocessors_title,
    };

    if (titleMap[pageId]) {
      document.title = titleMap[pageId];
    }

    const descriptionMap = {
      home: meta.home_description,
      subscribe: meta.subscribe_description,
    };

    const description = document.querySelector('meta[name="description"]');
    if (description && descriptionMap[pageId]) {
      description.setAttribute("content", descriptionMap[pageId]);
    }

    document.querySelectorAll("[data-i18n]").forEach((node) => {
      const key = node.getAttribute("data-i18n");
      const value = key ? resolveKey(key) : undefined;
      if (value != null) {
        node.textContent = value;
      }
    });

    document.querySelectorAll("[data-i18n-html]").forEach((node) => {
      const key = node.getAttribute("data-i18n-html");
      const value = key ? resolveKey(key) : undefined;
      if (value != null) {
        setLimitedRichText(node, value);
      }
    });

    if (faqList && Array.isArray(active.faq?.items)) {
      faqList.replaceChildren();

      active.faq.items.forEach((item, index) => {
        const details = document.createElement("details");
        details.className = "faq-item";
        if (index === 0) details.open = true;

        const summary = document.createElement("summary");
        summary.className = "faq-question";

        const questionCopy = document.createElement("span");
        questionCopy.className = "faq-question-copy";

        const indexLabel = document.createElement("span");
        indexLabel.className = "faq-index";
        indexLabel.textContent = String(index + 1).padStart(2, "0");

        const question = document.createElement("span");
        question.className = "faq-question-text";
        question.textContent = item.q;

        const marker = document.createElement("span");
        marker.className = "faq-marker";
        marker.setAttribute("aria-hidden", "true");
        marker.textContent = "+";

        questionCopy.append(indexLabel, question);
        summary.append(questionCopy, marker);

        const answer = document.createElement("div");
        answer.className = "faq-answer";

        item.a.forEach((paragraph) => {
          const p = document.createElement("p");
          p.textContent = paragraph;
          answer.appendChild(p);
        });

        details.append(summary, answer);
        faqList.appendChild(details);
      });
    }

    langButtons.forEach((button) => {
      button.setAttribute(
        "aria-pressed",
        button.getAttribute("data-lang-switch") === lang ? "true" : "false"
      );
    });
  };

  let currentLanguage = resolveInitialLanguage();
  applyLanguage(currentLanguage);

  langButtons.forEach((button) => {
    button.addEventListener("click", () => {
      const next = button.getAttribute("data-lang-switch");
      if (!next || next === currentLanguage) return;
      currentLanguage = next;
      window.localStorage.setItem(langStorageKey, currentLanguage);
      applyLanguage(currentLanguage);
    });
  });

  const revealables = document.querySelectorAll(".reveal");
  const storySteps = Array.from(document.querySelectorAll(".story-step"));
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const root = document.documentElement;
  const header = document.querySelector(".site-header");

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        }
      },
      { threshold: 0.14 }
    );

    revealables.forEach((node) => observer.observe(node));
  } else {
    revealables.forEach((node) => node.classList.add("is-visible"));
  }

  if (storySteps.length) {
    const activateStep = (activeStep) => {
      storySteps.forEach((step) => {
        step.classList.toggle("is-active", step === activeStep);
      });
    };

    if ("IntersectionObserver" in window) {
      const stepObserver = new IntersectionObserver(
        (entries) => {
          const visible = entries
            .filter((entry) => entry.isIntersecting)
            .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

          if (visible?.target) {
            activateStep(visible.target);
          }
        },
        {
          threshold: [0.35, 0.5, 0.7],
          rootMargin: "-12% 0px -12% 0px",
        }
      );

      storySteps.forEach((step) => stepObserver.observe(step));
    } else {
      activateStep(storySteps[0]);
    }
  }

  if (!reducedMotion) {
    let ticking = false;

    const syncMotion = () => {
      const scrollY = window.scrollY || 0;
      if (header) {
        header.classList.toggle("is-scrolled", scrollY > 16);
      }
      ticking = false;
    };

    window.addEventListener(
      "scroll",
      () => {
        if (ticking) return;
        ticking = true;
        window.requestAnimationFrame(syncMotion);
      },
      { passive: true }
    );

    syncMotion();
  } else if (header) {
    header.classList.remove("is-scrolled");
  }

  function appendInlineContent(parent, value) {
    const parts = value.split(/(`[^`]+`)/g);

    parts.forEach((part) => {
      if (!part) return;

      if (part.startsWith("`") && part.endsWith("`") && part.length >= 2) {
        const code = document.createElement("code");
        code.textContent = part.slice(1, -1);
        parent.appendChild(code);
        return;
      }

      parent.appendChild(document.createTextNode(part));
    });
  }

  function setLimitedRichText(node, value) {
    const fragment = document.createDocumentFragment();
    const tokenPattern = /<br\s*\/?>|<span>(.*?)<\/span>/gi;
    let lastIndex = 0;
    let match;

    while ((match = tokenPattern.exec(value)) !== null) {
      const textBefore = value.slice(lastIndex, match.index);
      if (textBefore) {
        fragment.appendChild(document.createTextNode(textBefore));
      }

      if (match[0].toLowerCase().startsWith("<br")) {
        fragment.appendChild(document.createElement("br"));
      } else {
        const span = document.createElement("span");
        span.textContent = match[1] || "";
        fragment.appendChild(span);
      }

      lastIndex = tokenPattern.lastIndex;
    }

    const trailingText = value.slice(lastIndex);
    if (trailingText) {
      fragment.appendChild(document.createTextNode(trailingText));
    }

    node.replaceChildren(fragment);
  }

  function renderMarkdownFragment(markdown) {
    const lines = markdown.replace(/\r\n/g, "\n").split("\n");
    const fragment = document.createDocumentFragment();
    let paragraph = [];
    let listType = null;
    let listNode = null;

    const flushParagraph = () => {
      if (!paragraph.length) return;
      const p = document.createElement("p");
      appendInlineContent(p, paragraph.join(" "));
      fragment.appendChild(p);
      paragraph = [];
    };

    const flushList = () => {
      if (!listNode) return;
      fragment.appendChild(listNode);
      listType = null;
      listNode = null;
    };

    for (const rawLine of lines) {
      const line = rawLine.trimEnd();
      const trimmed = line.trim();

      if (!trimmed) {
        flushParagraph();
        flushList();
        continue;
      }

      const heading = trimmed.match(/^(#{1,6})\s+(.*)$/);
      if (heading) {
        flushParagraph();
        flushList();
        const level = heading[1].length;
        const element = document.createElement(`h${level}`);
        appendInlineContent(element, heading[2]);
        fragment.appendChild(element);
        continue;
      }

      const bullet = trimmed.match(/^- (.*)$/);
      if (bullet) {
        flushParagraph();
        if (listType !== "ul") {
          flushList();
          listType = "ul";
          listNode = document.createElement("ul");
        }
        const item = document.createElement("li");
        appendInlineContent(item, bullet[1]);
        listNode.appendChild(item);
        continue;
      }

      const ordered = trimmed.match(/^\d+\.\s+(.*)$/);
      if (ordered) {
        flushParagraph();
        if (listType !== "ol") {
          flushList();
          listType = "ol";
          listNode = document.createElement("ol");
        }
        const item = document.createElement("li");
        appendInlineContent(item, ordered[1]);
        listNode.appendChild(item);
        continue;
      }

      flushList();
      paragraph.push(trimmed);
    }

    flushParagraph();
    flushList();
    return fragment;
  }

  const docShell = document.querySelector(".doc-shell[data-doc]");
  if (docShell) {
    const docPath = docShell.getAttribute("data-doc");
    fetch(docPath)
      .then((response) => {
        if (!response.ok) {
          throw new Error("Failed to load document");
        }
        return response.text();
      })
      .then((markdown) => {
        docShell.replaceChildren(renderMarkdownFragment(markdown));
        docShell.classList.add("is-visible");
      })
      .catch(() => {
        const message = document.createElement("p");
        message.textContent = "We couldn't load this page.";
        docShell.replaceChildren(message);
        docShell.classList.add("is-visible");
      });
  }

  const forms = document.querySelectorAll(".signup-form");

  const buildMailto = (payload) => {
    const subject = encodeURIComponent("Mixroom beta signup");
    const body = encodeURIComponent(
      [
        "Mixroom beta signup",
        "",
        `Name: ${payload.name}`,
        `Email: ${payload.email}`,
        `Newsletter opt-in: ${payload.newsletter ? "Yes" : "No"}`,
      ].join("\n")
    );

    return `mailto:contact@mixroom.ai?subject=${subject}&body=${body}`;
  };

  forms.forEach((form) => {
    const feedback = form.querySelector(".form-feedback");

    form.addEventListener("submit", async (event) => {
      event.preventDefault();

      if (!form.reportValidity()) {
        return;
      }

      const formData = new FormData(form);
      const payload = {
        name: String(formData.get("name") || "").trim(),
        email: String(formData.get("email") || "").trim(),
        newsletter: formData.get("newsletter") === "on",
      };

      const mailto = buildMailto(payload);
      feedback.textContent = "Thanks for subscribing!";

      try {
        if (navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(
            [
              "Mixroom beta signup",
              `Name: ${payload.name}`,
              `Email: ${payload.email}`,
              `Newsletter opt-in: ${payload.newsletter ? "Yes" : "No"}`,
            ].join("\n")
          );
        }
      } catch (_) {
        // Clipboard is only a convenience fallback.
      }

      window.location.href = mailto;
      form.reset();
    });
  });
})();
