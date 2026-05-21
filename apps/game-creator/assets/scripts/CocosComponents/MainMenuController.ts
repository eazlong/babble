/**
 * MainMenuController - Main menu scene controller.
 * Handles SpiritCoach fly-in animation, welcome greeting, language selection,
 * and game start flow.
 */

import { _decorator, Component, Node, tween, Vec3, Button, director, UIOpacity, EventHandler } from 'cc'
import { CCGlobalState } from '../Integration/CCGlobalState'
import { HybridAPI } from '../Utils/HybridAPI'
import { CoachOverlay } from './CoachOverlay'
import { AudioManager } from '../game-client/audio/AudioManager'
const { ccclass, property } = _decorator

@ccclass('MainMenuController')
export class MainMenuController extends Component {
  @property(Node) menuPanel: Node | null = null
  @property(CoachOverlay) coachOverlay: CoachOverlay | null = null

  private hybridAPI: HybridAPI | null = null
  private audioManager: AudioManager | null = null
  private selectedLang: string = 'zh'

  private newGameButton: Button | null = null
  private continueButton: Button | null = null
  private langZhButton: Button | null = null
  private langEnButton: Button | null = null

  start() {
    this.hybridAPI = new HybridAPI()
    this.hybridAPI.pingServices()
    this.audioManager = new AudioManager()

    this.selectedLang = this.getSavedLanguage()

    // Hide menu panel until coach finishes flying in
    if (this.menuPanel) {
      this.menuPanel.active = false
    }

    this.newGameButton = this.menuPanel?.getChildByName('NewGameButton')?.getComponent(Button) ?? null
    this.continueButton = this.menuPanel?.getChildByName('ContinueButton')?.getComponent(Button) ?? null
    this.langZhButton = this.menuPanel?.getChildByName('LangZhButton')?.getComponent(Button) ?? null
    this.langEnButton = this.menuPanel?.getChildByName('LangEnButton')?.getComponent(Button) ?? null

    const clickEventHandler = new EventHandler();
    clickEventHandler.target = this.node; // 这个 node 节点是你的事件处理代码组件所属的节点
    clickEventHandler.component = 'MainMenuController';// 这个是脚本类名
    clickEventHandler.handler = 'onSelectLanguage';
    clickEventHandler.customEventData = 'zh';
    this.langZhButton?.clickEvents.push(clickEventHandler);

    const enClickEventHandler = new EventHandler();
    enClickEventHandler.target = this.node;
    enClickEventHandler.component = 'MainMenuController';
    enClickEventHandler.handler = 'onSelectLanguage';
    enClickEventHandler.customEventData = 'en';
    this.langEnButton?.clickEvents.push(enClickEventHandler); 

    // Fly-in animation for SpiritCoach
    this.coachOverlay?.flyInFrom(new Vec3(800, 0, 0), new Vec3(0, 100, 0), 4, () => {
      this.onFlyInComplete()
    })

  }

  /**
   * Called after fly-in animation completes.
   * Shows welcome greeting and reveals menu panel.
   */
  private onFlyInComplete(): void {
    const welcomeText = this.selectedLang === 'en'
      ? 'Hello! Ready to learn magic English? Pick your language!'
      : '你好！准备好学习魔法英语了吗？选择你的语言吧！'

    this.showCoachMessage(welcomeText)

    if (this.menuPanel) {
      this.menuPanel.active = true
      this.menuPanel.interactable = true
      // const uiOpacity = this.menuPanel.getComponent(UIOpacity) || this.menuPanel.addComponent(UIOpacity)
      // uiOpacity.opacity = 0
      // tween(uiOpacity)
      //   .to(0.3, { opacity: 255 })
      //   .start()
    }
    this.updateLanguageButtons()

    // this.updateContinueButton()
  }

  /**
   * Show a dialogue bubble from the coach and play TTS audio.
   */
  async showCoachMessage(text: string): Promise<void> {
    this.coachOverlay?.showHint(text, 'neutral')

    // Play TTS audio
    if (this.hybridAPI && this.audioManager) {
      try {
        const result = await this.hybridAPI.synthesizeTTS(text, 'spirit', this.selectedLang)
        console.log('TTS result:', result)
        if (result?.audio_data) {
          await this.audioManager.playAudioFromBase64(result.audio_data, result.format)
        }
      } catch (err) {
        console.warn('TTS playback failed:', err)
      }
    }
  }

  /**
   * Player selected a language.
   */
  async onSelectLanguage(lang: string): Promise<void> {
    console.log('Language selected:', lang)

    this.selectedLang = lang
    localStorage.setItem('linguaquest_lang', lang)

    const confirmText = lang === 'en'
      ? 'Great! English mode! Let\'s go!'
      : '好的！中文模式！出发吧！'

    this.showCoachMessage(confirmText)
    this.updateLanguageButtons()

    await this.enterGameScene()
  }

  /**
   * Start a new game - initialize GameWorld and enter first scene.
   */
  async onStartNewGame(): Promise<void> {
    if (this.newGameButton) this.newGameButton.interactable = false

    this.showCoachMessage(
      this.selectedLang === 'en' ? 'Starting your adventure...' : '开始冒险……'
    )

    // Reset global state for new game
    const state = CCGlobalState.getInstance()
    state.reset()

    await this.enterGameScene()
  }

  /**
   * Continue from saved progress.
   */
  async onContinueGame(): Promise<void> {
    if (this.continueButton) this.continueButton.interactable = false

    this.showCoachMessage(
      this.selectedLang === 'en' ? 'Welcome back! Continuing...' : '欢迎回来！继续冒险……'
    )

    await this.enterGameScene()
  }

  private async enterGameScene(): Promise<void> {
    this.node.emit('start_game', { language: this.selectedLang })

    await new Promise((resolve) => setTimeout(resolve, 500))

    director.loadScene('SpiritForest')
  }

  private getSavedLanguage(): string {
    return localStorage.getItem('linguaquest_lang') || 'zh'
  }

  private hasSaveData(): boolean {
    try {
      const save = localStorage.getItem('linguaquest_save')
      return save !== null
    } catch {
      return false
    }
  }

  private updateLanguageButtons(): void {
    // Visually highlight the selected language button
    if (this.langZhButton) {
      // this.langZhButton.interactable = this.selectedLang !== 'zh'
      // this.langZhButton.active = true
      // this.langZhButton.interactable = true
      // this.langZhButton.node.setPosition(new Vec3(-300, 0, 0))
      tween(this.langZhButton.node)
      .to(0.5, { position: new Vec3(-300, 0, 0) }, { easing: 'quadIn' })
      .start()
    }
    if (this.langEnButton) {
      // this.langEnButton.interactable = this.selectedLang !== 'en'
      // this.langEnButton.active = true
      // this.langEnButton.interactable = true
      // this.langEnButton.node.setPosition(new Vec3(300, 0, 0))
      tween(this.langEnButton.node)
      .to(0.5, { position: new Vec3(300, 0, 0) }, { easing: 'quadIn' })
      .start()
    }
  }

  private updateContinueButton(): void {
    const hasSave = this.hasSaveData()
    if (this.continueButton) {
      this.continueButton.interactable = hasSave
      const uiOpacity = this.continueButton.node.getComponent(UIOpacity)
        || this.continueButton.node.addComponent(UIOpacity)
      uiOpacity.opacity = hasSave ? 255 : 100
    }
  }
}
