# DeepSeek-V4.1-Flash

自己实现的 WebGL 小引擎，将花篮、群山与田野放进可转向、可跳跃的骑行场景。

- 运行环境：DeepSeek Harness
- 模型标注：DeepSeek-V4.1-Flash · 界面标记 1017
- 界面任务耗时：45 分 36 秒
- 费用：¥2.24
- Tokens：43,141,343
- API 请求：161
- 界面显示速率：261 tok/s
- 界面缓存命中率：99.7%
- 界面 Tokens：43.1M tok（近似值；精确合计仍采用账单）
- 界面过程：1 轮、160 步（与 API 请求次数分别记录）
- 渲染：自写 WebGL 引擎

## 体验

直接在支持 WebGL 的现代浏览器中打开 [原始成品](artifact/index.html)。此文件为原样归档，可离线运行。模型源文件和原始成品不为展示站做视觉改写。

- 拖拽旋转与缩放
- 速度、暂停与视角切换
- WASD 转向与空格跳跃
- 昼夜切换与三套配色
- 双腿与脚踏联动

## 数据来源

用户提供的任务界面截图：DeepSeek-V4.1-Flash，界面标记 1017。

任务界面显示的完成耗时；测试环境和过程未统一。

账单截图范围为近 30 天；用户确认 ¥2.24、161 次 API 请求、43,141,343 Tokens 全部来自本次任务。Tokens 为账单合计，未提供输入、输出或缓存拆分。

用户更新的 DeepSeek Harness 任务截图底栏。速率和缓存命中率均按界面显示记录，未提供计算方式；43.1M tok 为近似显示。1 轮、160 步是界面过程计数，与账单的 161 次 API 请求分别记录。

- [deepseek-session.png](../../evidence/deepseek-session.png)
- [deepseek-usage.png](../../evidence/deepseek-usage.png)

## 完整性

原始 HTML 的 SHA-256：

`07c562e697cf312e94f69b3425f4e26682a439a9ec472756d9eb2aaa96e9cfb0`

本页记录的是一次任务的最终成品，不表示模型整体能力排名，也不声称一次生成。
