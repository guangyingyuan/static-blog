---
title: NYTime Objective-C 程式規範
layout: default
comments: true
date: 2013-11-03 12:23:01
categories:
- iOS
tags:
- iOS
- Programming
---
Objective-C 程式規範，參考於紐約時報所規範之程式風格。

![](/images/msic/objc.png)

<!--more-->

## 點語法

 始终使用點語法來存取**屬性**，存取其他實例時應用**中括號[]**。

**建議：**
```objc
view.backgroundColor = [UIColor orangeColor];
[UIApplication sharedApplication].delegate;
```

**反對：**
```objc
[view setBackgroundColor:[UIColor orangeColor]];
UIApplication.sharedApplication.delegate;
```

## 間距

* 永遠不要使用制表符號（tab）間隔。確保在Xcode 中設定了此偏好。
* 方法的大括號和其他的大括號（`if`/`else`/`switch`/`while` 等等）始終和宣告在同一行開始，在新的一行結束。

**建議：**
```objc
if (user.isHappy) {
// Do something
}
else {
// Do something else
}
```
* 方法之間空格一行，這樣有助於視覺的清晰度和程式碼組織性。在方法中的功能區塊之間應該使用空白分開，但往往可能建立一個新的方法。
* `@synthesize` 和 `@dynamic` 在實現中都須佔一個新行。


## 條件判斷

條件判斷主要部分不需使用大括號來防止[出錯][Condiationals_1]。這些錯誤包含添加第二行(程式碼)，並希望它是if 語法的一部分時。還有另外一種[更危險的][Condiationals_2]，當 if 語法裡面的一行被註解掉，下一行就會在不經意間成為了這個 if 語法的一部分。此外，這種風格也更符合所有其他的條件判斷，因此也更容易檢查。

**建議：**
```objc
if (!error) {
    return success;
}
```

**反對：**
```objc
if (!error)
    return success;
```

或

```objc
if (!error) return success;
```


[Condiationals_1]:https://github.com/NYTimes/objective-c-style-guide/issues/26#issuecomment-22074256
[Condiationals_2]:http://programmers.stackexchange.com/a/16530

### 三元運算式

三元運算式以 (**條件**) ? **成立** : **不成立**;

只有當它可以增加程式碼清晰度或整潔時才使用。單一的條件都應該優先考虑使用。多條件時通常使用 if 會更好懂，或者重構成實體變數。

**建議：**
```objc
result = (a > b) ? x : y;
```

**反對：**
```objc
result = a > b ? x = c > d ? c : d : y;
```
## Switch case
由於使用Switch case會針對所有條件是進行處理，需針對所有條件實現，以及用區塊對case做工作區別，確保區塊的正確需給予一項約束：

**建議：**
```objc
MyEnum types = MyEnumValueA;

switch (types) {
    case MyEnumValueA:{
        break;
    }
    case MyEnumValueB: {
        break;
    }
    case MyEnumValueC: {
        break;
    }
    default: {

    }
}
```

**反對：**
```objc
int types = 0;

switch (types) {
    case 0:
        break;
    case 1:
        break;
    case 2:
        break;
    default:
}
```

## 錯誤處理

當引用一個回傳錯誤參數（error parameter）的方法時，應該針對回傳值，而非錯誤變數。

**建議：**
```objc
NSError *error;
if (![self trySomethingWithError:&error]) {
    // 錯誤處理
}
```

**反對：**
```objc
NSError *error;
[self trySomethingWithError:&error];
if (error) {
    // 錯誤處理
}
```
一些Apple的API在成功的情况下會寫一些垃圾值给錯誤參數(如果非空)，所以針對錯誤變數可能會造成虛假结果 (或者崩溃)。

## 方法

方法宣告中，在 -/+ 符號後應該有一個空格。方法片段之間也應該有一個空格。

**建議：**
```
- (void)setExampleText:(NSString *)text image:(UIImage *)image;
```

## 變數

變數名稱應該盡可能命名具有描述性。除了 `for()` 迴圈外，其他情况都應該避免使用單字母的變數名。
星號表示指標變數，例如：`NSString *text` 不要寫成 `NSString* text` 或者 `NSString * text` ，常數除外。
盡量定義屬性來取代直接使用實體變數。除了初始化方法（`init`， `initWithCoder:`等）， `dealloc` 方法和自定義的setters和 getters内部，應避免直接存取實體變數。更多有關在初始化方法和 dealloc方法中使用存取器方法的資訊，可參考[這邊][Variables_1]。

**建議：**

```objc
@interface NYTSection: NSObject

@property (nonatomic) NSString *headline;

@end
```

**反對：**

```objc
@interface NYTSection : NSObject {
    NSString *headline;
}

@property (nonatomic) NSString* string;
```

[Variables_1]:https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmPractical.html#//apple_ref/doc/uid/TP40004447-SW6

#### 變數屬性限制

當涉及到[ARC][Variable_Qualifiers_1]變數屬性限制時，
限制保留字 (`__strong`, `__weak`, `__unsafe_unretained`, `__autoreleasing`) 應該位於Class與變數名稱之間，如：`NSString * __weak text`。

[Variable_Qualifiers_1]:(https://developer.apple.com/library/ios/releasenotes/objectivec/rn-transitioningtoarc/Introduction/Introduction.html#//apple_ref/doc/uid/TP40011226-CH1-SW4)

### 命名

盡可能遵照Apple的命名法則，尤其那些涉及到[記憶體管理規範][Naming_1]，（[NonARC][Naming_2]）的。

**長一點**和**描述性**的方法名稱和變數名稱都不错。

**建議：**

```objc
UIButton *settingsButton;
```

**反對：**

```objc
UIButton *setBut;
```
類別名稱和常數名稱應該使用三個字母當開頭（例如 `KRT`），但 Core Data 實體名稱可以省略。為了程式碼的乾淨，常數應該使用相關類別的名字作為開頭，並使用駝峰式命名法。

**建議：**
```objc
static const NSTimeInterval NYTArticleViewControllerNavigationFadeAnimationDuration = 0.3;
```

**反對：**

```objc
static const NSTimeInterval fadetime = 1.7;
```

**屬性**和**區域變數**應該使用**駝峰式命名法**，並且首字母小寫。

為了保持一致，實體變數應該使用駝峰式命名，且首字母小寫，以下底線為開頭。這是**LLVM**的自動合成的實體變數一致。
**如果LLVM可以自動合成變數，那就讓它自動合成吧。**

**建議：**
```objc
@synthesize descriptiveVariableName = _descriptiveVariableName;
```

**反對：**
```objc
id varnm;
```

[Naming_1]:https://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/MemoryMgmt/Articles/MemoryMgmt.html

[Naming_2]:http://stackoverflow.com/a/2865194/340508

### 註解

當需要的时候，註解應該被用來解释 **為什麼** 特定程式做了某些事情。所使用之任何註解必須保持最新，否則就刪掉。

通常應避免一大塊註解，程式碼應該盡量作為自身的檔案，只需要隔幾行寫幾句說明。這並不適用於那些用來生成檔案的註解。

### init 和 dealloc

`dealloc` 方法應該放在**實作檔**最上面，並且剛好在 `@synthesize` 和 `@dynamic` 保留字的後面。在任何類別中，`init` 都應該直接放在 `dealloc` 方法的下方。

`init` 方法的結構應該像這樣：

```objc
- (instancetype)init {
    self = [super init]; // 呼叫指定的初始化方法
    if (self) {
        // Custom initialization
    }
    return self;
}
```

### 字面變數

當創建 `NSString`， `NSDictionary`， `NSArray`，和 `NSNumber` 物件的不可變實體時，都應該使用字面量。要注意 `nil` 值不能傳給 `NSArray` 和 `NSDictionary` 字面變數，這樣做會導致崩潰。

**建議：**

```objc
NSArray *names = @[@"Brian", @"Matt", @"Chris", @"Alex", @"Steve", @"Paul"];
NSDictionary *productManagers = @{@"iPhone" : @"Kate", @"iPad" : @"Kamal", @"Mobile Web" : @"Bill"};
NSNumber *shouldUseLiterals = @YES;
NSNumber *buildingZIPCode = @10018;
```

**反對：**

```objc
NSArray *names = [NSArray arrayWithObjects:@"Brian", @"Matt", @"Chris", @"Alex", @"Steve", @"Paul", nil];
NSDictionary *productManagers = [NSDictionary dictionaryWithObjectsAndKeys: @"Kate", @"iPhone", @"Kamal", @"iPad", @"Bill", @"Mobile Web", nil];
NSNumber *shouldUseLiterals = [NSNumber numberWithBool:YES];
NSNumber *buildingZIPCode = [NSNumber numberWithInteger:10018];
```

### CGRect函式

當存取一個 `CGRect` 的 `x`， `y`， `width`， `height` 时，應該使用[`CGGeometry` 函式][CGRect-Functions_1]取代直接存取結構體成員。Apple的 `CGGeometry` 参考中說到：

> All functions described in this reference that take CGRect data structures as inputs implicitly standardize those rectangles before calculating their results. For this reason, your applications should avoid directly reading and writing the data stored in the CGRect data structure. Instead, use the functions described here to manipulate rectangles and to retrieve their characteristics.

**建議：**

```objc
CGRect frame = self.view.frame;

CGFloat x = CGRectGetMinX(frame);
CGFloat y = CGRectGetMinY(frame);
CGFloat width = CGRectGetWidth(frame);
CGFloat height = CGRectGetHeight(frame);
```

**反對：**

```objc
CGRect frame = self.view.frame;

CGFloat x = frame.origin.x;
CGFloat y = frame.origin.y;
CGFloat width = frame.size.width;
CGFloat height = frame.size.height;
```

[CGRect-Functions_1]:http://developer.apple.com/library/ios/#documentation/graphicsimaging/reference/CGGeometry/Reference/reference.html

### 常數

常數使用字元、字串 字面變數或數值變數，因為常數可以輕易重用，且可以快速改變而不需要查找和替換。常數應該宣告為 `static` 常數而不是 `#define` ，除非很明確的要當做marco來使用。

**建議：**

```objc
static NSString * const NYTAboutViewControllerCompanyName = @"The New York Times Company";

static const CGFloat NYTImageThumbnailHeight = 50.0;
```

**反對：**

```objc
#define CompanyName @"The New York Times Company"

#define thumbnailHeight 2
```

### 枚舉類型

當使用 `enum` 時，建議使用新的基礎類型規範，因為它具有更强的類型檢查和程式碼補全功能。現在的SDK 包含了一個marco來建議使用者利用新的基礎類型 - `NS_ENUM()`

**建議：**
```objc
typedef NS_ENUM(NSInteger, NYTAdRequestState) {
    NYTAdRequestStateInactive,
    NYTAdRequestStateLoading
};
```

### 位元碼

當用到位元碼時，使用 `NS_OPTIONS` marco。

**舉例：**

```objc
typedef NS_OPTIONS(NSUInteger, NYTAdCategory) {
    NYTAdCategoryAutos      = 1 << 0,
    NYTAdCategoryJobs       = 1 << 1,
    NYTAdCategoryRealState  = 1 << 2,
    NYTAdCategoryTechnology = 1 << 3
};
```

### 私有屬性

私有屬性應該宣告在類別實作檔的延展(匿名的類目)中。有名字的類目(例如 `NYTPrivate` 或 `private`) 永遠都不應該使用，除非要擴展其他類別。

**建議：**

```objc
@interface NYTAdvertisement ()

@property (nonatomic, strong) GADBannerView *googleAdView;
@property (nonatomic, strong) ADBannerView *iAdView;
@property (nonatomic, strong) UIWebView *adXWebView;

@end
```

### 圖片命名

圖片名稱應該被統一命名，以保持組織的完整。它們應該被命名為一個說明它們**用途的駝峰式字串**，其次是自定義類別或屬性的無前綴名字（如果有的話），然後進一步說明**顏色**與**對應的解析度識別(ex:iPhone 6 and iPhone 5為@2x)**或 **圖片展示位置**，最後是它們的**狀態**。

**建議：**

* `RefreshBarButtonItem` / `RefreshBarButtonItem@2x` 和 `RefreshBarButtonItemSelected` / `RefreshBarButtonItemSelected@2x`
* `ArticleNavigationBarWhite` / `ArticleNavigationBarWhite@2x` 和 `ArticleNavigationBarBlackSelected` / `ArticleNavigationBarBlackSelected@2x`.


[對應的解析度識別](https://developer.apple.com/library/ios/documentation/UserExperience/Conceptual/MobileHIG/IconMatrix.html)

圖片目錄中被用於類似目地的圖片應歸入各自組中。
最後確保圖片存放於**Images.xcassets**。


### 布林

因為 `nil` 解析為 `NO`，所以没有必要在條件中與它進行比較。永遠不要直接和 `YES` 進行比較，因為 `YES` 被定義為 1，而 `BOOL` 可以多達八位元。

這使得整個檔案有更多的一致性和更大的視覺清晰度。

**建議：**
```objc
if (!someObject) {
}
```

**反對：**

```objc
if (someObject == nil) {
}
```

**對於 `BOOL` 來說, 這有兩種用法:**

```objc
if (isAwesome)
if (![someObject boolValue])
```

**反對：**

```objc
if ([someObject boolValue] == NO)
if (isAwesome == YES) // 絕對不要這麼做
```

如果一個 `BOOL` 屬性名稱是一個形容詞，屬性可以省略 “is” 前缀，但為 get 存取器指定一個慣用的名稱，例如：

```objc
@property (assign, getter=isEditable) BOOL editable;
```

內容和範例來自 [Cocoa 命名指南][Booleans_1] 。

[Booleans_1]:https://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/CodingGuidelines/Articles/NamingIvarsAndTypes.html#//apple_ref/doc/uid/20001284-BAJGIIJE


### 單一實例

單例對象應該使用執行緒安全的模式創建共享的實例。

```objc
+ (instancetype)sharedInstance {
   static id sharedInstance = nil;

   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      sharedInstance = [[self alloc] init];
   });

   return sharedInstance;
}
```
這將會預防[有時可能產生的許多崩潰][Singletons_1]。

[Singletons_1]:http://cocoasamurai.blogspot.com/2011/04/singletons-your-doing-them-wrong.html


### Xcode

为了避免檔案複雜，實體檔案與目錄應該保持與Xcode同步。Xcode 建立的任何群組（group）都必须在檔案系统有相應的映射。為了更清晰，程式碼不僅應該按照**類型**進行分组，也可以根據**功能**進行分组。


![](/images/msic/code_group.png)

如果可以的話，盡可能一直打開 target Build Settings 中 "Treat Warnings as Errors" 以及一些[額外的警告][Xcode-project_1]。如果你需要忽略指定的警告,使用 [Clang 的編譯特性][Xcode-project_2] 。


[Xcode-project_1]:http://boredzo.org/blog/archives/2009-11-07/warnings

[Xcode-project_2]:http://clang.llvm.org/docs/UsersManual.html#controlling-diagnostics-via-pragmas

### 其他Objective-C風格指南

* [Google](http://google-styleguide.googlecode.com/svn/trunk/objcguide.xml)
* [GitHub](https://github.com/github/objective-c-conventions)
* [Adium](https://trac.adium.im/wiki/CodingStyle)
* [Sam Soffes](https://gist.github.com/soffes/812796)
* [CocoaDevCentral](http://cocoadevcentral.com/articles/000082.php)
* [Luke Redpath](http://lukeredpath.co.uk/blog/my-objective-c-style-guide.html)
* [Marcus Zarra](http://www.cimgf.com/zds-code-style-guide/)
