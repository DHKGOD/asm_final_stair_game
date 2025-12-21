# 小朋友下樓梯 (教學詳解版 v13.0)
# 這個版本特別加強了中文註解，適合初學者學習 MIPS 組合語言與遊戲邏輯。
#
# [遊戲規則]
# 1. 玩家(黃色)要不斷往下跳，踩在綠色樓梯上。
# 2. 如果撞到天花板(刺)或掉到最底部，會扣血 (HP -4)。
# 3. 樓梯上有青色星星，吃到可以加分 (+800分)。
# 4. 分數集滿 3200 分會升級，回復血量 (+4 HP)。
# 5. 操作：'a' 向左，'d' 向右，'o' 暫停，'p' 繼續。

# -----------------------------------------------------------------------------
# .data 區段：用來宣告變數 (Variables)
# 這裡就像 C 語言的 int x = 10;
# -----------------------------------------------------------------------------
.data
    # --- 顯示設定 ---
    # 這是 MARS Bitmap Display 的記憶體起始位址 (固定值)
    displayAddress: .word 0x10008000
    screenWidth:    .word 64         # 螢幕寬度 64 格
    screenHeight:   .word 32         # 螢幕高度 32 格

    # --- 顏色定義 (16進位 RGB) ---
    # 0x00RRGGBB (紅、綠、藍)
    colorBG:        .word 0x000000   # 黑色 (背景)
    colorPlayer:    .word 0xFFFF00   # 黃色 (玩家)
    colorPlat:      .word 0x00FF00   # 綠色 (樓梯)
    colorHP:        .word 0xFF0000   # 紅色 (血條)
    colorItem:      .word 0x00FFFF   # 青色 (星星道具)
    colorScore:     .word 0x0000FF   # 藍色 (下方積分條)
    
    # --- 遊戲變數 ---
    playerX:        .word 32         # 玩家 X 座標 (左右)
    playerY:        .word 10         # 玩家 Y 座標 (上下)
    hp:             .word 16         # 生命值 (Max 16)
    score:          .word 0          # 目前累積能量 (滿3200歸零)
    totalScore:     .word 0          # 遊戲總分
    frameCounter:   .word 0          # 幀數計數器 (用來控制速度)

    # --- 平台資料 (陣列 Array) ---
    # platCount: 總共有 8 個平台
    platCount:      .word 8
    # platX: 每個平台的 X 座標
    platX:          .word 10, 50, 30, 5, 45, 20, 55, 15
    # platY: 每個平台的 Y 座標
    platY:          .word 20, 24, 28, 32, 36, 40, 44, 48
    # platItem: 每個平台上有沒有道具 (0=沒有, 1=有)
    platItem:       .word 0, 1, 0, 0, 1, 0, 0, 0

    # --- Stack 資料結構 (無限接關用) ---
    # 我們用這一塊空間來記錄「上一次踩過的樓梯是幾號」
    platStack:      .space 400       # 預留 400 bytes 的空間
    stackPtr:       .word 0          # 堆疊指標 (目前存到哪了)
    lastIdx:        .word -1         # 紀錄上一次踩到的樓梯編號

    # --- 文字訊息 (String) ---
    # 用 .asciiz 宣告以 null 結尾的字串
    str_start:      .asciiz "Teaching Mode: Check comments for logic!\n"
    str_hp:         .asciiz "HP: "
    str_score:      .asciiz " Total: "
    str_newline:    .asciiz "\n"
    str_item:       .asciiz "Star! +800 pts.\n"
    str_levelup:    .asciiz ">>> Energy Full! HP +4 <<<\n"
    str_respawn:    .asciiz "Ouch! Big Damage (-4 HP).\n"
    str_gameover:   .asciiz "\nGame Over! Score: "
    str_paused:     .asciiz "PAUSED. Press 'p' to resume.\n"
    str_resumed:    .asciiz "RESUMED.\n"

# -----------------------------------------------------------------------------
# .text 區段：程式碼邏輯 (Code)
# -----------------------------------------------------------------------------
.text
.globl main

# === 程式進入點 ===
main:
    # 1. 在下方 Console 印出歡迎訊息
    li $v0, 4               # Syscall 4 = 印字串
    la $a0, str_start       # 載入字串位址
    syscall

    # 2. 初始化變數 (Reset Variables)
    li $t0, 32
    sw $t0, playerX         # 設定玩家初始 X = 32
    li $t0, 5
    sw $t0, playerY         # 設定玩家初始 Y = 5
    li $t0, 16
    sw $t0, hp              # 設定初始 HP = 16
    sw $zero, score         # 分數歸零
    sw $zero, totalScore    # 總分歸零
    
    # 初始化 Stack
    sw $zero, stackPtr      # 指標歸零
    li $t0, -1
    sw $t0, lastIdx         # 上次樓梯設為 -1 (代表還沒踩過)

# =============================================================================
# 遊戲主迴圈 (Game Loop)
# 這是遊戲的心臟，會不斷重複執行： 清除 -> 輸入 -> 計算 -> 繪圖
# =============================================================================
GameLoop:
    # --- 1. 計時器更新 ---
    lw $t0, frameCounter    # 讀取目前幀數
    addi $t0, $t0, 1        # +1
    sw $t0, frameCounter    # 存回去
    
    # --- 2. 自動加分機制 ---
    lw $t1, score           # 讀取能量條分數
    addi $t1, $t1, 1        # +1
    sw $t1, score
    lw $t2, totalScore      # 讀取總分
    addi $t2, $t2, 1        # +1
    sw $t2, totalScore

    # --- 3. 檢查是否升級 ---
    jal CheckLevelUp        # 跳去檢查函式

    # --- 4. 畫面清除 (Clear Screen) ---
    # 原理：先把舊的東西都畫成黑色 (colorBG)
    lw $a1, playerX         # 準備玩家 X
    lw $a2, playerY         # 準備玩家 Y
    lw $a3, colorBG         # 準備顏色：黑色
    jal DrawPlayerPixel     # 呼叫畫點函式 -> 把玩家塗黑

    lw $a0, colorBG
    lw $a1, colorBG
    jal DrawPlatforms       # 把所有樓梯塗黑

    jal EraseScoreBar       # 把下面藍條塗黑
    jal UpdateHPBar         # 更新(重畫)血條

    # --- 5. 鍵盤輸入偵測 (Input) ---
    # MMIO 記憶體位置：0xffff0000 (狀態), 0xffff0004 (資料)
    li $t0, 0xffff0000
    lw $t1, 0($t0)          # 讀取狀態
    beq $t1, 0, Physics     # 如果是 0 (沒按鍵)，直接跳去物理運算
    
    # 有按鍵，讀取內容
    lw $t2, 0xffff0004
    beq $t2, 111, PauseGame   # 如果是 'o' (111) -> 暫停
    beq $t2, 97, move_left    # 如果是 'a' (97)  -> 向左
    beq $t2, 100, move_right  # 如果是 'd' (100) -> 向右
    j Physics                 # 其他按鍵忽略，跳去物理

# --- 暫停功能區 ---
PauseGame:
    # 因為剛剛把畫面擦黑了，暫停時要補畫一次，不然會全黑
    lw $a0, colorPlat       # 樓梯色
    lw $a1, colorItem       # 道具色
    jal DrawPlatforms       # 畫樓梯
    jal DrawScoreBar        # 畫藍條
    lw $a1, playerX
    lw $a2, playerY
    lw $a3, colorPlayer     # 玩家色
    jal DrawPlayerPixel     # 畫玩家
    
    li $v0, 4
    la $a0, str_paused
    syscall                 # 印出 PAUSED 文字

PauseLoop:
    # 這是一個死迴圈 (Infinite Loop)，直到按下 'p'
    li $t0, 0xffff0000
    lw $t1, 0($t0)
    beq $t1, 0, PauseLoop     # 沒按鍵 -> 繼續等
    lw $t2, 0xffff0004
    beq $t2, 112, ResumeGame  # 按下 'p' (112) -> 解除暫停
    j PauseLoop

ResumeGame:
    li $v0, 4
    la $a0, str_resumed
    syscall
    j Physics                 # 回到物理運算

# --- 左右移動邏輯 ---
move_left:
    lw $t0, playerX
    subi $t0, $t0, 1        # X 減 1 (向左)
    blt $t0, 0, Physics     # 如果 X < 0 (出界)，取消移動
    sw $t0, playerX         # 存回新位置
    j Physics

move_right:
    lw $t0, playerX
    addi $t0, $t0, 1        # X 加 1 (向右)
    bgt $t0, 63, Physics    # 如果 X > 63 (出界)，取消移動
    sw $t0, playerX
    j Physics

# =============================================================================
# 物理運算 (Physics Engine)
# 處理：樓梯移動、重力下墜、碰撞判定
# =============================================================================
Physics:
    # 1. 樓梯移動 (每 5 幀動一次)
    lw $t0, frameCounter
    rem $t1, $t0, 5         # frameCounter % 5
    bnez $t1, CheckGravity  # 餘數不為 0 -> 跳過移動
    jal UpdatePlatforms     # 餘數為 0 -> 呼叫樓梯更新

CheckGravity:
    # 2. 檢查是否踩到樓梯
    jal CheckStandOnPlatform
    # CheckStandOnPlatform 會回傳 $v0 (1=踩到, 0=沒踩到)
    beq $v0, 1, SnapToPlatform # 踩到了！跳去吸附邏輯
    
    # 3. 沒踩到 -> 重力下墜 (每 2 幀掉一次)
    lw $t0, frameCounter
    andi $t0, $t0, 1        # frameCounter % 2
    bnez $t0, CheckBounds   # 跳過下墜
    
    lw $s1, playerY
    addi $s1, $s1, 1        # Y 加 1 (往下掉)
    sw $s1, playerY
    j CheckBounds

SnapToPlatform:
    # 4. 吸附機制 (黏在樓梯上)
    # 當樓梯往上移，玩家也要跟著往上
    subi $s1, $v1, 1        # 玩家Y = 樓梯Y - 1
    sw $s1, playerY

    # --- [Stack 紀錄路徑] ---
    # 這是為了掉下去時能回到上一個位置
    lw $t8, lastIdx         # 讀取上次踩的樓梯編號
    beq $t8, $a0, CheckItemLogic # 如果跟上次一樣，就不存
    
    # 是新樓梯！存檔！
    sw $a0, lastIdx         # 更新 lastIdx
    
    lw $t9, stackPtr        # 讀取 Stack 指標
    li $t7, 400             # 檢查是否滿了
    bge $t9, $t7, CheckItemLogic
    
    la $t6, platStack       # Stack 起始位址
    add $t6, $t6, $t9       # 計算目前位址
    sw $a0, 0($t6)          # 把樓梯 ID 存進去 (Push)
    
    addi $t9, $t9, 4        # 指標往後移 4 bytes
    sw $t9, stackPtr        # 存回指標
    # -----------------------

CheckItemLogic:
    # 5. 檢查有無道具 (星星)
    la $t1, platItem        # 道具陣列
    sll $t0, $a0, 2         # Offset = ID * 4
    add $t1, $t1, $t0
    lw $t2, 0($t1)          # 讀取該樓梯有沒有星星
    beq $t2, 1, EatItem     # 有 (1) -> 吃掉
    j CheckBounds

EatItem:
    sw $zero, 0($t1)        # 把星星變不見 (設為0)
    
    # 分數 + 800
    lw $t3, score
    addi $t3, $t3, 800  
    sw $t3, score
    
    lw $t4, totalScore
    addi $t4, $t4, 800
    sw $t4, totalScore
    
    li $v0, 4
    la $a0, str_item
    syscall
    jal PrintStatus         # 更新文字狀態
    j CheckBounds

# =============================================================================
# 邊界判定 (Boundary Check)
# 處理：撞到天花板、掉到虛空
# =============================================================================
CheckBounds:
    lw $s1, playerY
    ble $s1, 1, HitCeiling    # 如果 Y <= 1 (撞頂)
    bge $s1, 31, FallRespawn  # 如果 Y >= 31 (掉底)
    j DrawAll                 # 都沒事 -> 去繪圖

FallRespawn:
    # --- 掉落虛空 ---
    # 1. 扣血 (傷害 4)
    lw $t0, hp
    subi $t0, $t0, 4
    sw $t0, hp
    blez $t0, GameOver        # 如果血量 <= 0 -> 遊戲結束
    
    # 2. Stack Peek (讀取存檔點)
    lw $t9, stackPtr
    blez $t9, DefaultRespawn  # 如果 Stack 是空的 -> 預設重生
    
    # 讀取最後一筆資料 (指標 - 4)
    subi $t6, $t9, 4
    la $t7, platStack
    add $t7, $t7, $t6
    lw $t5, 0($t7)            # 取得存檔的樓梯 ID
    
    # 3. 傳送玩家回去
    la $t1, platX
    sll $t4, $t5, 2
    add $t1, $t1, $t4
    lw $s0, 0($t1)
    sw $s0, playerX           # 設定 X 座標
    
    la $t2, platY
    add $t2, $t2, $t4
    lw $s1, 0($t2)
    subi $s1, $s1, 1
    sw $s1, playerY           # 設定 Y 座標
    
    sw $t5, lastIdx           # 記得更新 lastIdx
    
    li $v0, 4
    la $a0, str_respawn       # 印出重生訊息
    syscall
    jal PrintStatus
    j DrawAll

DefaultRespawn:
    # 備案：如果 Stack 是空的，就隨便把人放在上面
    li $s1, 2
    sw $s1, playerY
    li $t8, -1
    sw $t8, lastIdx
    li $v0, 4
    la $a0, str_respawn
    syscall
    jal PrintStatus
    j DrawAll

HitCeiling:
    # --- 撞到天花板 ---
    # 1. 扣血 (傷害 4)
    lw $t0, hp
    subi $t0, $t0, 4
    sw $t0, hp
    # 2. 往下彈開 (避免黏在天花板一直扣血)
    addi $s1, $s1, 2
    sw $s1, playerY
    blez $t0, GameOver
    jal PrintStatus
    j DrawAll

# =============================================================================
# 繪圖區 (Rendering)
# 負責把所有東西畫到螢幕上
# =============================================================================
DrawAll:
    # 1. 畫平台與道具
    lw $a0, colorPlat       # 設定參數 $a0 = 綠色
    lw $a1, colorItem       # 設定參數 $a1 = 青色
    jal DrawPlatforms       # 呼叫畫平台函式
    
    # 2. 畫下方藍色積分條
    jal DrawScoreBar
    # 3. 畫上方紅色血條
    jal UpdateHPBar

    # 4. 畫玩家 (黃色)
    lw $a3, colorPlayer
    j CallDrawPlayer

CallDrawPlayer:
    lw $a1, playerX
    lw $a2, playerY
    jal DrawPlayerPixel
    
    # --- 速度控制 ---
    li $v0, 32              # Syscall 32 = Sleep (毫秒)
    li $a0, 30              # 暫停 30ms (約 33 FPS)
    syscall
    j GameLoop              # 跳回主迴圈，下一幀開始！

GameOver:
    li $v0, 4
    la $a0, str_gameover
    syscall
    li $v0, 1
    lw $a0, totalScore      # 印出最終總分
    syscall
    li $v0, 10              # Syscall 10 = 結束程式
    syscall

# =============================================================================
# 輔助函式區 (Helper Functions)
# =============================================================================

# --- 檢查升級 (Check Level Up) ---
CheckLevelUp:
    lw $t0, score
    li $t1, 3200
    blt $t0, $t1, CLU_Done  # 分數 < 3200 -> 離開
    
    # 升級了！
    sw $zero, score         # 1. 藍條歸零
    
    lw $t2, hp
    addi $t2, $t2, 4        # 2. 血量 +4
    bgt $t2, 16, CapHP      # 超過上限就修正
    j SaveHP
CapHP:
    li $t2, 16              # 上限是 16
SaveHP:
    sw $t2, hp
    
    li $v0, 4
    la $a0, str_levelup     # 3. 印出升級訊息
    syscall
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal PrintStatus
    lw $ra, 0($sp)
    addi $sp, $sp, 4
CLU_Done:
    jr $ra

# --- 更新平台位置 (Update Platforms) ---
UpdatePlatforms:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    lw $t0, platCount
    la $t1, platX
    la $t2, platY
    la $t8, platItem
    li $t3, 0
UP_Loop:
    beq $t3, $t0, UP_Done   # 迴圈結束
    lw $t5, 0($t2)
    subi $t5, $t5, 1        # Y 減 1 (平台往上飄)
    blt $t5, 0, UP_Reset    # 如果 Y < 0 (飄出去了) -> 重置
    sw $t5, 0($t2)
    j UP_Next
UP_Reset:
    li $t5, 31              # 重置到底部 Y=31
    sw $t5, 0($t2)
    li $v0, 42
    li $a0, 0
    li $a1, 55
    syscall
    sw $a0, 0($t1)          # 隨機產生新的 X 座標
    
    li $v0, 42
    li $a0, 0
    li $a1, 10
    syscall
    blt $a0, 3, Spawn       # 30% 機率產生星星
    sw $zero, 0($t8)        # 沒中 -> 設為 0
    j UP_Next
Spawn:
    li $t9, 1
    sw $t9, 0($t8)          # 中了 -> 設為 1 (有星星)
UP_Next:
    # 指標往後移，處理下一個平台
    addi $t1, $t1, 4
    addi $t2, $t2, 4
    addi $t8, $t8, 4
    addi $t3, $t3, 1
    j UP_Loop
UP_Done:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# --- 畫平台與道具 (Draw Platforms) ---
DrawPlatforms:
    addi $sp, $sp, -28
    sw $ra, 0($sp)
    # ... (保存暫存器) ...
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)
    move $s3, $a0           # $s3 = 平台顏色
    move $s4, $a1           # $s4 = 道具顏色
    lw $s0, platCount
    la $t8, platX
    la $t9, platY
    la $s2, platItem
    li $s1, 0
DP_Loop:
    beq $s1, $s0, DP_Done
    lw $t4, 0($t8)          # X
    lw $a2, 0($t9)          # Y
    addi $t5, $t4, 8        # 平台長度 8
DL_Loop:
    bge $t4, $t5, CheckStar # 畫完 8 格，去檢查星星
    move $a1, $t4
    move $a3, $s3           # 設定顏色
    
    # 呼叫畫點 (要保存暫存器)
    addi $sp, $sp, -20
    sw $t8, 0($sp)
    sw $t9, 4($sp)
    sw $t4, 8($sp)
    sw $t5, 12($sp)
    sw $a2, 16($sp)
    jal DrawPlayerPixel
    lw $t8, 0($sp)
    lw $t9, 4($sp)
    lw $t4, 8($sp)
    lw $t5, 12($sp)
    lw $a2, 16($sp)
    addi $sp, $sp, 20
    
    addi $t4, $t4, 1
    j DL_Loop
CheckStar:
    lw $t7, 0($s2)
    beqz $t7, DP_Next       # 沒星星 -> 下一個
    lw $a1, 0($t8)
    addi $a1, $a1, 3        # 星星位置在平台中間 (X+3)
    lw $a2, 0($t9)
    subi $a2, $a2, 1        # 星星在平台上方 (Y-1)
    move $a3, $s4           # 設定青色
    addi $sp, $sp, -8
    sw $t8, 0($sp)
    sw $t9, 4($sp)
    jal DrawPlayerPixel     # 畫星星
    lw $t8, 0($sp)
    lw $t9, 4($sp)
    addi $sp, $sp, 8
DP_Next:
    addi $t8, $t8, 4
    addi $t9, $t9, 4
    addi $s2, $s2, 4
    addi $s1, $s1, 1
    j DP_Loop
DP_Done:
    # ... (恢復暫存器) ...
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    lw $s4, 20($sp)
    addi $sp, $sp, 28
    jr $ra

# --- 畫單點像素 (Draw Pixel) ---
# 這是最底層的繪圖函式，直接寫入記憶體
DrawPlayerPixel:
    # 邊界檢查 (防止畫到螢幕外面報錯)
    blt $a1, 0, DP_End
    bge $a1, 64, DP_End
    blt $a2, 0, DP_End
    bge $a2, 32, DP_End
    
    lw $t0, displayAddress  # 基底位址
    lw $t1, screenWidth     # 64
    
    # 計算位址公式: Address = Base + (Y * Width + X) * 4
    mul $t2, $a2, $t1       # Y * 64
    add $t2, $t2, $a1       # + X
    sll $t2, $t2, 2         # * 4 (因為一個 pixel 佔 4 bytes)
    add $t2, $t2, $t0       # + Base
    
    sw $a3, 0($t2)          # 把顏色 ($a3) 寫進去
DP_End:
    jr $ra

# --- 畫下方藍條 (Draw Score Bar) ---
DrawScoreBar:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    lw $t2, score
    div $t2, $t2, 50        # 長度 = 分數 / 50
    li $t0, 0
DSB_Loop:
    bge $t0, $t2, DSB_End
    move $a1, $t0
    li $a2, 31              # Y = 31 (最底層)
    lw $a3, colorScore      # 藍色
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t2, 4($sp)
    jal DrawPlayerPixel
    lw $t0, 0($sp)
    lw $t2, 4($sp)
    addi $sp, $sp, 8
    addi $t0, $t0, 1
    j DSB_Loop
DSB_End:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# --- 擦除下方藍條 ---
EraseScoreBar:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    li $t0, 0
    li $t1, 64
ESB_Loop:
    beq $t0, $t1, ESB_End
    move $a1, $t0
    li $a2, 31
    lw $a3, colorBG         # 黑色
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal DrawPlayerPixel
    lw $t0, 0($sp)
    lw $t1, 4($sp)
    addi $sp, $sp, 8
    addi $t0, $t0, 1
    j ESB_Loop
ESB_End:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# --- 畫上方血條 (Update HP Bar) ---
UpdateHPBar:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    li $t0, 0
    li $t1, 64
ClearHP:                    # 先整條塗黑
    beq $t0, $t1, DrawHP
    move $a1, $t0
    li $a2, 0
    lw $a3, colorBG
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal DrawPlayerPixel
    lw $t0, 0($sp)
    lw $t1, 4($sp)
    addi $sp, $sp, 8
    addi $t0, $t0, 1
    j ClearHP
DrawHP:                     # 再畫紅線
    lw $t2, hp
    sll $t1, $t2, 2         # 長度 = HP * 4
    li $t0, 0
DH_Loop:
    bge $t0, $t1, HP_End
    move $a1, $t0
    li $a2, 0
    lw $a3, colorHP
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal DrawPlayerPixel
    lw $t0, 0($sp)
    lw $t1, 4($sp)
    addi $sp, $sp, 8
    addi $t0, $t0, 1
    j DH_Loop
HP_End:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# --- 碰撞檢測 (Check Collision) ---
CheckStandOnPlatform:
    addi $sp, $sp, -4
    sw $s3, 0($sp)
    lw $t0, platCount
    la $t1, platX
    la $t2, platY
    li $t3, 0
    lw $s0, playerX
    lw $s1, playerY 
    addi $s1, $s1, 1        # 檢查玩家「腳下」那一格
CS_Loop:
    beq $t3, $t0, CS_No     # 檢查完所有平台 -> 沒踩到
    lw $t5, 0($t2)          # 平台 Y
    sub $t6, $s1, $t5       # 玩家腳Y - 平台Y
    beq $t6, 0, CheckX      # 高度一樣 -> 檢查 X
    beq $t6, 1, CheckX      # 陷進去一點點 (吸附容錯) -> 檢查 X
    j CS_Next
CheckX:
    lw $t4, 0($t1)          # 平台 X
    blt $s0, $t4, CS_Next   # 玩家太左邊 -> 沒踩到
    addi $t7, $t4, 7        # 平台長度 7 (稍微縮小一點避免邊緣Bug)
    bgt $s0, $t7, CS_Next   # 玩家太右邊 -> 沒踩到
    
    # 踩到了！
    li $v0, 1               # 回傳 1
    move $v1, $t5           # 回傳平台 Y
    move $a0, $t3           # 回傳平台 ID
    lw $s3, 0($sp)
    addi $sp, $sp, 4
    jr $ra
CS_Next:
    addi $t1, $t1, 4
    addi $t2, $t2, 4
    addi $t3, $t3, 1
    j CS_Loop
CS_No:
    li $v0, 0               # 回傳 0
    lw $s3, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# --- 印出狀態文字 (Print Status) ---
PrintStatus:
    li $v0, 4
    la $a0, str_hp
    syscall
    li $v0, 1
    lw $a0, hp
    syscall
    li $v0, 4
    la $a0, str_score
    syscall
    li $v0, 1
    lw $a0, totalScore
    syscall
    li $v0, 4
    la $a0, str_newline
    syscall
    jr $ra