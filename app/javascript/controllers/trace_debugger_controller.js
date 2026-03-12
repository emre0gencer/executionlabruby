import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { traces: Array, currentStep: { type: Number, default: 0 } }
  static targets = ["stepLabel", "opcode", "pc", "stack", "locals", "callStack"]

  connect() {
    this.render()
    this._keyHandler = this._onKey.bind(this)
    window.addEventListener("keydown", this._keyHandler)
  }

  disconnect() {
    window.removeEventListener("keydown", this._keyHandler)
  }

  prev() {
    if (this.currentStepValue > 0) {
      this.currentStepValue -= 1
    }
  }

  next() {
    if (this.currentStepValue < this.tracesValue.length - 1) {
      this.currentStepValue += 1
    }
  }

  currentStepValueChanged() {
    this.render()
  }

  render() {
    const traces = this.tracesValue
    if (!traces || traces.length === 0) return

    const step = this.currentStepValue
    const trace = traces[step]
    if (!trace) return

    const total = traces.length

    if (this.hasStepLabelTarget) {
      this.stepLabelTarget.textContent = `Step ${step + 1} / ${total}`
    }

    if (this.hasOpcodeTarget) {
      const instr = trace.instruction || {}
      this.opcodeTarget.textContent = instr.opcode || "—"
    }

    if (this.hasPcTarget) {
      const instr = trace.instruction || {}
      this.pcTarget.textContent = instr.pc != null ? `pc=${instr.pc}` : ""
    }

    if (this.hasStackTarget) {
      const stack = trace.stack || []
      if (stack.length === 0) {
        this.stackTarget.innerHTML = '<span class="text-slate-500 italic text-xs">empty</span>'
      } else {
        this.stackTarget.innerHTML = [...stack].reverse().map((v, i) =>
          `<div class="flex items-center gap-2 py-0.5 ${i === 0 ? 'text-indigo-300 font-semibold' : 'text-slate-300'}">
            <span class="text-slate-500 text-xs w-5 text-right">${stack.length - 1 - i}</span>
            <span>${this._formatValue(v)}</span>
          </div>`
        ).join("")
      }
    }

    if (this.hasLocalsTarget) {
      const locals = trace.locals || []
      if (locals.length === 0) {
        this.localsTarget.innerHTML = '<span class="text-slate-500 italic text-xs">none</span>'
      } else {
        this.localsTarget.innerHTML = locals.map((v, i) =>
          `<div class="flex items-center gap-2 py-0.5">
            <span class="text-slate-500 text-xs w-5 text-right">${i}</span>
            <span class="text-slate-300">${this._formatValue(v)}</span>
          </div>`
        ).join("")
      }
    }

    if (this.hasCallStackTarget) {
      const callStack = trace.call_stack || trace.callStack || []
      if (callStack.length === 0) {
        this.callStackTarget.innerHTML = '<span class="text-slate-500 italic text-xs">none</span>'
      } else {
        this.callStackTarget.innerHTML = [...callStack].reverse().map((frame, i) =>
          `<div class="py-0.5 ${i === 0 ? 'text-indigo-300 font-semibold' : 'text-slate-400'}">
            ${typeof frame === 'object' ? (frame.function || frame.name || JSON.stringify(frame)) : frame}
          </div>`
        ).join("")
      }
    }
  }

  _formatValue(v) {
    if (v === null || v === undefined) return '<span class="text-slate-500">nil</span>'
    if (typeof v === 'boolean') return `<span class="text-yellow-400">${v}</span>`
    if (typeof v === 'number') return `<span class="text-cyan-400">${v}</span>`
    if (typeof v === 'string') return `<span class="text-green-400">"${v}"</span>`
    return `<span class="text-slate-300">${JSON.stringify(v)}</span>`
  }

  _onKey(e) {
    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return
    if (e.key === "ArrowLeft") { e.preventDefault(); this.prev() }
    if (e.key === "ArrowRight") { e.preventDefault(); this.next() }
  }
}
