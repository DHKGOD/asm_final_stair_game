#include <stdio.h>
#include <stdlib.h>
#include <conio.h>   // 用於按鍵偵測 (_kbhit, _getch)
#include <windows.h> // 用於游標控制 (gotoxy) 和 延遲 (Sleep)
#include <time.h>    // 用於隨機數

// =============================================================================
// 全域變數 (Global Variables)
// 對應 MIPS 的 .data 區段，存放遊戲所有的資料
// =============================================================================

// 螢幕大小設定 (寬 64 x 高 32)
#define SCREEN_WIDTH 64
#define SCREEN_HEIGHT 32

// --- 畫面緩衝區 (雙重緩衝技術) ---
// displayBuffer: 這一幀要畫什麼，我們把東西先填在這裡
int displayBuffer[SCREEN_HEIGHT][SCREEN_WIDTH];
// previousBuffer: 上一幀畫了什麼，用來比對差異，只更新有變動的地方 (防閃爍)
int previousBuffer[SCREEN_HEIGHT][SCREEN_WIDTH];

// --- 符號定義 (用整數代表不同的物件) ---
// 程式邏輯用數字運算，最後顯示時再轉成符號
#define EMPTY 0      // 空氣
#define PLAYER 1     // 玩家 (P)
#define PLATFORM 2   // 樓梯 (=)
#define ITEM 3       // 星星 (*)
#define HP_BAR 4     // 血條 (|)
#define SCORE_BAR 5  // 分數條 (-)

// --- 遊戲狀態變數 ---
int playerX = 32;    // 玩家 X 座標 (0~63)
int playerY = 10;    // 玩家 Y 座標 (0~31)
int hp = 16;         // 生命值 (Max 16)
int score = 0;       // 總分 (只有吃星星才增加)
int frameCounter = 0;// 幀數計數器 (用來控制樓梯移動速度)

// --- 平台資料 (陣列) ---
int platCount = 8;   // 總共有 8 個平台
// 每個平台的 X 座標
int platX[8] = {10, 50, 30, 5, 45, 20, 55, 15};
// 每個平台的 Y 座標
int platY[8] = {20, 24, 28, 32, 36, 40, 44, 48};
// 每個平台是否有星星 (0=無, 1=有)
int platItem[8] = {0, 1, 0, 0, 1, 0, 0, 0}; 

// --- Stack 堆疊 (無限回溯功能) ---
// 用來記錄玩家踩過哪些樓梯，掉下去時可以回到上一個
int platStack[100]; // 堆疊陣列
int stackPtr = 0;   // 堆疊指標 (目前存到哪了)
int lastIdx = -1;   // 紀錄上一次踩到的樓梯編號 (避免重複存)

// =============================================================================
// 系統輔助函式 (Helper Functions)
// 處理 Windows 視窗相關的底層操作
// =============================================================================

// 將游標移動到指定的 (x, y) 位置
// 這樣我們就可以在螢幕的任何地方印字，不用一直清空畫面
void gotoxy(int x, int y) {
    COORD coord;
    coord.X = x;
    coord.Y = y;
    SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), coord);
}

// 隱藏終端機那個閃爍的游標，讓畫面看起來更乾淨像遊戲
void HideCursor() {
    CONSOLE_CURSOR_INFO cursorInfo;
    GetConsoleCursorInfo(GetStdHandle(STD_OUTPUT_HANDLE), &cursorInfo);
    cursorInfo.bVisible = FALSE; 
    SetConsoleCursorInfo(GetStdHandle(STD_OUTPUT_HANDLE), &cursorInfo);
}

// =============================================================================
// 函式宣告 (Function Prototypes)
// 告訴編譯器有哪些函式可以使用
// =============================================================================
void GameLoop();
void Physics();
void CheckGravity();
void SnapToPlatform(int platIdx);
void CheckItemLogic(int platIndex);
void EatItem(int platIndex);
void CheckBounds();
void FallRespawn();
void DefaultRespawn();
void HitCeiling();
void DrawAll();
void RenderScreen();
void UpdatePlatforms();
int CheckStandOnPlatform();
void GameOver();
void DrawScoreBar();
void UpdateHPBar();
void CheckLevelUp(); // 補上宣告

// =============================================================================
// 主程式 (Main Function)
// 程式的進入點
// =============================================================================
int main() {
    // 1. 設定視窗大小 (寬80, 高40)，避免字太長導致換行錯亂
    system("mode con: cols=80 lines=40");
    HideCursor();      // 隱藏游標
    srand(time(NULL)); // 初始化隨機數種子 (讓每次玩的星星位置不同)

    // 2. 初始化畫面緩衝區
    // 將 previousBuffer 設為 -1，強制第一幀全部重畫
    for(int y=0; y<SCREEN_HEIGHT; y++) {
        for(int x=0; x<SCREEN_WIDTH; x++) {
            previousBuffer[y][x] = -1;
            displayBuffer[y][x] = EMPTY;
        }
    }

    printf("Game Start! Press any key...\n");
    _getch();      // 等待玩家按任意鍵
    system("cls"); // 清空畫面，開始遊戲

    // 3. 進入遊戲主迴圈
    GameLoop();

    return 0;
}

// =============================================================================
// 遊戲邏輯核心 (Game Logic)
// =============================================================================
void GameLoop() {
    // 無窮迴圈，直到遊戲結束
    while (1) {
        frameCounter++; // 計數器 +1
        
        // 檢查是否達到升級分數 (滿 2000 分回血)
        CheckLevelUp();

        // --- 清空繪圖區 ---
        // 邏輯上把 displayBuffer 全部填成 EMPTY (空氣)
        // 注意：這裡還沒畫到螢幕上，只是在記憶體裡清空
        for(int y=0; y<SCREEN_HEIGHT; y++) {
            for(int x=0; x<SCREEN_WIDTH; x++) {
                displayBuffer[y][x] = EMPTY;
            }
        }

        // --- 輸入偵測 (Input) ---
        if (_kbhit()) { // 如果有按鍵被按下
            char key = _getch(); // 讀取按鍵值
            
            if (key == 'o') { // 'o' 暫停
                // 進入死迴圈，直到按下 'p' 才跳出
                while(1) { if(_kbhit() && _getch() == 'p') break; }
            }
            if (key == 'a') { // 'a' 向左
                playerX--;
                if (playerX < 0) playerX = 0; // 邊界檢查
            }
            if (key == 'd') { // 'd' 向右
                playerX++;
                if (playerX > 63) playerX = 63;
            }
        }

        // --- 物理運算 (Physics) ---
        Physics();
        
        // --- 繪圖與顯示 (Draw) ---
        DrawAll();
    }
}

// --- 物理運算 ---
void Physics() {
    // 樓梯移動速度控制
    // 每 3 幀移動一次，這樣比每幀移動慢，比每5幀快，比較順暢
    if (frameCounter % 3 == 0) {
        UpdatePlatforms();
    }
    // 檢查重力 (是否要掉下去)
    CheckGravity();
}

// --- 更新平台位置 ---
void UpdatePlatforms() {
    for (int i = 0; i < platCount; i++) {
        platY[i]--; // Y 減 1 (平台往上飄)
        
        // 如果平台飄出螢幕上方 (Y < 0)
        if (platY[i] < 0) { 
            platY[i] = 31;          // 重置到底部
            platX[i] = rand() % 55; // 隨機產生新的 X 位置
            
            // 30% 機率產生星星 (rand % 10 < 3)
            if ((rand() % 10) < 3) platItem[i] = 1;
            else platItem[i] = 0;
        }
    }
}

// --- 重力檢查 ---
void CheckGravity() {
    // 檢查是否踩到平台
    int platIdx = CheckStandOnPlatform();
    
    if (platIdx != -1) {
        // 踩到了 (回傳平台編號) -> 執行吸附邏輯
        SnapToPlatform(platIdx); 
    } else {
        // 沒踩到 -> 下墜
        // 每 2 幀掉 1 格 (控制下墜速度)
        if (frameCounter % 2 == 0) playerY++; 
        
        // 檢查有沒有撞到邊界
        CheckBounds();
    }
}

// --- 檢查是否站在平台上 ---
// 回傳值：踩到的平台編號，如果沒踩到回 -1
int CheckStandOnPlatform() {
    int footY = playerY + 1; // 腳的位置
    
    for (int i = 0; i < platCount; i++) {
        // 1. 檢查高度：腳是否剛好在平台上方 (或陷進去一點點)
        if (footY == platY[i] || footY == platY[i] + 1) {
            // 2. 檢查寬度：玩家 X 是否在平台範圍內 (平台寬度設為 7)
            if (playerX >= platX[i] && playerX <= platX[i] + 7) {
                return i; // 找到了！回傳編號
            }
        }
    }
    return -1; // 都沒找到
}

// --- 吸附與存檔邏輯 ---
void SnapToPlatform(int platIdx) {
    // 強制把玩家 Y 設為平台上方一格 (黏在平台上)
    playerY = platY[platIdx] - 1;

    // --- Stack 邏輯 (關鍵功能) ---
    // 如果踩到的是「新的」樓梯 (跟上次不一樣)
    if (lastIdx != platIdx) {
        lastIdx = platIdx; // 更新上次樓梯編號
        
        // 把這個樓梯編號存入堆疊 (Push)
        if (stackPtr < 100) {
            platStack[stackPtr] = platIdx;
            stackPtr++;
        }
    }
    
    // 檢查這個樓梯上有沒有道具
    CheckItemLogic(platIdx);
}

// --- 檢查道具 ---
void CheckItemLogic(int platIndex) {
    if (platItem[platIndex] == 1) {
        EatItem(platIndex); // 有 -> 吃掉
    } else {
        CheckBounds();      // 無 -> 檢查邊界
    }
}

// --- 吃星星 ---
void EatItem(int platIndex) {
    platItem[platIndex] = 0; // 把星星變不見 (設為0)
    
    // [重點] 分數增加 (這是全遊戲唯一加分的地方)
    score += 500; 

    // [重點] 檢查升級 (每 2000 分)
    // 利用餘數運算：如果分數大於0 且 分數除以2000餘數為0 (整除)
    if (score > 0 && score % 2000 == 0) {
        hp += 4;          // 回血 +4
        if (hp > 16) hp = 16; // 上限 16
        
        // 在下方印出升級提示
        gotoxy(0, SCREEN_HEIGHT + 1);
        printf(">>> LEVEL UP! HP RESTORED! <<<       ");
    }
    
    CheckBounds();
}

// --- 邊界檢查 ---
void CheckBounds() {
    if (playerY <= 1) HitCeiling();      // 撞到天花板
    else if (playerY >= 31) FallRespawn(); // 掉到底部
}

// --- 掉落重生 (Stack Pop) ---
void FallRespawn() {
    hp -= 4; // 扣血
    if (hp <= 0) GameOver(); // 沒血了 -> 遊戲結束

    // 如果 Stack 是空的 (還沒踩過任何樓梯就掉下去)
    if (stackPtr <= 0) {
        DefaultRespawn();
        return;
    }
    
    // --- Stack Peek (讀取存檔) ---
    // 取出堆疊最上面的一個編號 (stackPtr - 1)
    int savedIdx = platStack[stackPtr - 1]; 
    
    // 把玩家傳送回那個樓梯的位置
    playerX = platX[savedIdx];
    playerY = platY[savedIdx] - 1;
    lastIdx = savedIdx;
    
    // 印出提示
    gotoxy(0, SCREEN_HEIGHT + 1);
    printf("Oops! Respawn at last step (-4 HP)   ");
}

// --- 預設重生 (沒存檔時) ---
void DefaultRespawn() {
    playerY = 2;   // 把人丟到最上面
    lastIdx = -1;
}

// --- 撞頭 ---
void HitCeiling() {
    hp -= 4;
    playerY += 2; // 往下彈開
    if (hp <= 0) GameOver();
    
    gotoxy(0, SCREEN_HEIGHT + 1);
    printf("Ouch! Hit Ceiling (-4 HP)            ");
}

// --- 遊戲結束 ---
void GameOver() {
    system("cls"); // 清空畫面
    printf("\n\n");
    printf("  ==============================\n");
    printf("    GAME OVER \n");
    printf("    Final Score: %d\n", score); // 顯示總分
    printf("  ==============================\n");
    printf("\n  Press any key to exit...");
    _getch();
    exit(0);
}

// =============================================================================
// 繪圖區 (Rendering)
// 負責把 buffer 裡的數字轉成圖形印出來
// =============================================================================
void DrawAll() {
    // 1. 把所有物件「填入」displayBuffer 二維陣列
    // 這一步只是在記憶體裡畫圖，還沒印出來
    
    // 畫平台與星星
    for (int i = 0; i < platCount; i++) {
        // 畫樓梯 (長度 8)
        for (int k = 0; k < 8; k++) {
            int px = platX[i] + k;
            int py = platY[i];
            // 邊界檢查，防止畫出界
            if(px >=0 && px < SCREEN_WIDTH && py >=0 && py < SCREEN_HEIGHT)
                displayBuffer[py][px] = PLATFORM;
        }
        // 畫星星 (在樓梯中間上方)
        if (platItem[i] == 1) {
            int sx = platX[i] + 3;
            int sy = platY[i] - 1;
            if(sx >=0 && sx < SCREEN_WIDTH && sy >=0 && sy < SCREEN_HEIGHT)
                displayBuffer[sy][sx] = ITEM;
        }
    }

    // 畫 UI (分數條與血條)
    DrawScoreBar(); 
    UpdateHPBar(); 

    // 畫玩家
    if(playerX >=0 && playerX < SCREEN_WIDTH && playerY >=0 && playerY < SCREEN_HEIGHT)
        displayBuffer[playerY][playerX] = PLAYER;

    // 2. 真正印到螢幕上 (呼叫 RenderScreen)
    RenderScreen();
    
    // 3. 延遲 (控制遊戲速度)
    // 60ms 大約是 15 FPS，速度適中且不會閃爍
    Sleep(60); 
}

// --- 畫下方藍色分數條 ---
void DrawScoreBar() {
    // [數學邏輯] 
    // 利用餘數 (%) 來讓藍條循環顯示
    // 分數 500 -> 長度 10
    // 分數 2000 -> 餘數 0 -> 長度 0 (藍條歸零)
    int length = (score % 2000) / 50; 
    
    for(int i=0; i<length && i<SCREEN_WIDTH; i++) 
        displayBuffer[31][i] = SCORE_BAR;
}

// --- 畫上方紅色血條 ---
void UpdateHPBar() {
    int length = hp * 4; // 16 * 4 = 64 (滿血剛好一條)
    for(int i=0; i<length && i<SCREEN_WIDTH; i++) 
        displayBuffer[0][i] = HP_BAR;
}

// --- 畫面渲染 (解決閃爍的關鍵) ---
void RenderScreen() {
    // 雙重緩衝：只更新有變動的字元
    for (int y = 0; y < SCREEN_HEIGHT; y++) {
        for (int x = 0; x < SCREEN_WIDTH; x++) {
            // 比對現在要畫的 (displayBuffer) 跟上次畫的 (previousBuffer)
            // 如果不一樣，才移動游標去更新，這樣就不會全螢幕重畫導致閃爍
            if (displayBuffer[y][x] != previousBuffer[y][x]) {
                gotoxy(x, y); // 移動游標
                
                int type = displayBuffer[y][x];
                // 根據代號印出符號
                if (type == EMPTY) printf(" ");
                else if (type == PLAYER) printf("O"); // 玩家
                else if (type == PLATFORM) printf("="); // 樓梯
                else if (type == ITEM) printf("*");   // 星星
                else if (type == HP_BAR) printf("|"); // 血條
                else if (type == SCORE_BAR) printf("-"); // 分數條
                
                // 更新舊的 buffer，記住這次畫了什麼
                previousBuffer[y][x] = type;
            }
        }
    }
    
    // 更新下方的文字狀態
    gotoxy(0, SCREEN_HEIGHT);
    printf("HP: %02d | Score: %05d", hp, score);
}

// 空函式 (為了對應上面的宣告，實際邏輯已整合在 EatItem)
void CheckLevelUp() {}