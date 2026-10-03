# 组件约定

## 按钮
- 主按钮：primary 底色，胶囊形（border-radius: 999px），padding 10px 20px
- 次按钮：透明底 + border，胶囊形
- 按压反馈：:active 时 scale(0.97)，transition 120ms ease-out
- 禁止：渐变、发光、非胶囊形的控制按钮

## 卡片
- 背景 surface，border 1px，圆角 16px（squircle 连续圆角），shadow.sm
- 内边距统一 16px
- 禁止：同屏出现 3 个以上同权重卡片堆叠

## 输入框
- 背景 surface，border 1px，圆角 12px（连续圆角）
- focus 时 border 变 primary，不加外发光

## 工具栏/导航栏（Liquid Glass 层）
- 使用 backdrop-filter: blur(20px) + saturate(180%)
- 背景 glassTint
- 必须启用交互反馈（按压缩放）

## 间距
- 组件内 8/12，组件间 16/24，区块间 32/48
- 禁止随手写 5px、7px、13px 这类非规范值
