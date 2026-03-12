import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  show(event) {
    const panel = event.params.panel

    this.tabTargets.forEach(tab => {
      const active = tab.dataset.tabsPanelParam === panel
      tab.classList.toggle("text-white", active)
      tab.classList.toggle("border-b-2", active)
      tab.classList.toggle("border-indigo-500", active)
      tab.classList.toggle("bg-slate-700/50", active)
      tab.classList.toggle("text-slate-400", !active)
    })

    this.panelTargets.forEach(p => {
      p.classList.toggle("hidden", p.dataset.tabsPanel !== panel)
    })
  }
}
