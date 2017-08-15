//
//  JotViewController.m
//  jot
//
//  Created by Laura Skelton on 4/30/15.
//
//

#import "JotViewController.h"
#import "JotDrawView.h"
#import "JotTextView.h"
#import "JotTextEditView.h"
#import "JotLabel.h"
#import <Masonry/Masonry.h>
#import "UIImage+Jot.h"
#import "JotDrawingContainer.h"
#import "UIImageView+ImageFrame.h"

NSString const* kDrawView = @"DrawView";
NSString const* kLabels = @"Labels";
NSString const* kDate = @"Date";

@interface JotViewController () <UIGestureRecognizerDelegate, JotTextEditViewDelegate, JotDrawingContainerDelegate, JotDrawViewDelegate>

@property (nonatomic, strong) UITapGestureRecognizer *tapRecognizer;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchRecognizer;
@property (nonatomic, strong) UIRotationGestureRecognizer *rotationRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, strong, readwrite) JotDrawingContainer *drawingContainer;
@property (nonatomic, strong) JotDrawView *drawView;
@property (nonatomic, strong) JotTextEditView *textEditView;
@property (nonatomic, strong) JotTextView *textView;
@property (nonatomic, weak) UIImageView *imageView;
@property (nonatomic, assign) CGPoint lastTapPoint;

@end

@implementation JotViewController

- (instancetype)init
{
    if ((self = [super init])) {
        _drawView = [JotDrawView new];
        _drawView.delegate = self;
        
        _textEditView = [JotTextEditView new];
        _textEditView.delegate = self;
        _textView = [JotTextView new];
        _drawingContainer = [JotDrawingContainer new];
        self.drawingContainer.delegate = self;
        self.drawingContainer.discreteGridSize = 0; // no grid
        
        _font = self.textView.font;
        _fontSize = self.textView.fontSize;
        _textAlignment = self.textView.textAlignment;
        _textColor = self.textView.textColor;
        _textString = @"";
        _drawingColor = self.drawView.strokeColor;
        _drawingStrokeWidth = self.drawView.strokeWidth;
        _textEditingInsets = self.textEditView.textEditingInsets;
        _initialTextInsets = self.textView.initialTextInsets;
        _state = JotViewStateDefault;
        
        self.textEditView.textAlignment = NSTextAlignmentLeft;
        
        _pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
        self.pinchRecognizer.delegate = self;
        
        _rotationRecognizer = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotateGesture:)];
        self.rotationRecognizer.delegate = self;
        
        _panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
        self.panRecognizer.delegate = self;
        
        _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
        self.tapRecognizer.delegate = self;
    }
    return self;
}

- (void)dealloc
{
    self.textEditView.delegate = nil;
    self.drawingContainer.delegate = nil;
}

- (void)setupForImageView:(UIImageView *)imageView {
    self.imageView = imageView;
    [_drawView setupForImageView:imageView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.drawingColor = [UIColor whiteColor];
    self.textColor = [UIColor whiteColor];
    self.view.backgroundColor = [UIColor clearColor];
    self.drawingContainer.clipsToBounds = YES;
    
    [self.view addSubview:self.drawingContainer];
    [self.drawingContainer mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(self.view);
        make.center.equalTo(self.view);
    }];
    
    [self.drawingContainer addSubview:self.drawView];
    [self.drawView mas_makeConstraints:^(MASConstraintMaker *make) {

        make.size.mas_equalTo(self.view);
        make.center.equalTo(self.view);
    }];
    
    [self.drawingContainer addSubview:self.textView];
    [self.textView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(self.view);
        make.center.equalTo(self.view);
    }];
    
    [self.view addSubview:self.textEditView];
    [self.textEditView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(self.view);
        make.center.equalTo(self.view);
    }];
    
    [self.drawingContainer addGestureRecognizer:self.tapRecognizer];
    [self.drawingContainer addGestureRecognizer:self.panRecognizer];
    [self.drawingContainer addGestureRecognizer:self.rotationRecognizer];
    [self.drawingContainer addGestureRecognizer:self.pinchRecognizer];
}

#pragma mark - Properties

- (void)setState:(JotViewState)state
{
    if (_state != state) {
        _state = state;
        
        self.textView.hidden =
        self.textEditView.isEditing = (state == JotViewStateEditingText);
        
        if (state == JotViewStateEditingText) {
            
            if ([self.delegate respondsToSelector:@selector(jotViewController:isEditingText:)]) {
                [self.delegate jotViewController:self isEditingText:YES];
            }
            if (![self.textView labelAtPosition:self.lastTapPoint]) {
                CGPoint labelPosition = CGPointEqualToPoint(self.lastTapPoint, CGPointZero)
                ? self.textView.center
                : self.lastTapPoint;
                JotLabel *label = [self.textView addLabelAtPosition:labelPosition];
                self.textEditView.textString = @"";
                self.textEditView.font = label.font;
                self.textEditView.textColor = label.textColor;
                self.lastTapPoint = CGPointZero;
            }
        }
		
		if (state != JotViewStateText && state != JotViewStateEditingText) {
			[self.textView deselectLabel];
		}
        
        self.drawingContainer.multipleTouchEnabled =
        self.tapRecognizer.enabled =
        self.panRecognizer.enabled =
        self.pinchRecognizer.enabled =
        self.rotationRecognizer.enabled = (state == JotViewStateText);
    }
}

- (void)setTextString:(NSString *)textString
{
	_textString = textString;
	if (![self.textView.textString isEqualToString:textString]) {
		self.textView.textString = textString;
	}
	if (![self.textEditView.textString isEqualToString:textString]) {
		self.textEditView.textString = textString;
	}
}

- (void)setFont:(UIFont *)font
{
	_font = font;
	self.textView.font =
	self.textEditView.font = font;
}

- (void)setFontSize:(CGFloat)fontSize
{
	_fontSize = fontSize;
	self.textView.fontSize =
	self.textEditView.fontSize = fontSize;
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment
{
	_textAlignment = textAlignment;
	self.textView.textAlignment =
	self.textEditView.textAlignment = textAlignment;
}

- (void)setTextColor:(UIColor *)textColor
{
	_textColor = textColor;
	self.textView.textColor =
	self.textEditView.textColor = textColor;
}

- (void)setInitialTextInsets:(UIEdgeInsets)initialTextInsets
{
	_initialTextInsets = initialTextInsets;
	self.textView.initialTextInsets = initialTextInsets;
}

- (void)setTextEditingInsets:(UIEdgeInsets)textEditingInsets
{
	_textEditingInsets = textEditingInsets;
	self.textEditView.textEditingInsets = textEditingInsets;
}

- (void)setFitOriginalFontSizeToViewWidth:(BOOL)fitOriginalFontSizeToViewWidth
{
	_fitOriginalFontSizeToViewWidth = fitOriginalFontSizeToViewWidth;
	self.textView.fitOriginalFontSizeToViewWidth = fitOriginalFontSizeToViewWidth;
	if (fitOriginalFontSizeToViewWidth) {
		self.textEditView.textAlignment = self.textAlignment;
	} else {
		self.textEditView.textAlignment = NSTextAlignmentLeft;
	}
}

- (void)setClipBoundsToEditingInsets:(BOOL)clipBoundsToEditingInsets
{
	_clipBoundsToEditingInsets = clipBoundsToEditingInsets;
	self.textEditView.clipBoundsToEditingInsets = clipBoundsToEditingInsets;
}

- (void)setDrawingColor:(UIColor *)drawingColor
{
    if (_drawingColor != drawingColor) {
        _drawingColor = drawingColor;
        self.drawView.strokeColor = drawingColor;
    }
}

- (void)setDrawingStrokeWidth:(CGFloat)drawingStrokeWidth
{
    if (_drawingStrokeWidth != drawingStrokeWidth) {
        _drawingStrokeWidth = drawingStrokeWidth;
        self.drawView.strokeWidth = drawingStrokeWidth;
    }
}

- (void)setDrawingConstantStrokeWidth:(BOOL)drawingConstantStrokeWidth
{
    if (_drawingConstantStrokeWidth != drawingConstantStrokeWidth) {
        _drawingConstantStrokeWidth = drawingConstantStrokeWidth;
        self.drawView.constantStrokeWidth = drawingConstantStrokeWidth;
    }
}

- (void)setDrawingLineDashed:(BOOL)drawingLineDashed
{
	_drawingLineDashed = drawingLineDashed;
	self.drawView.dashedLine = drawingLineDashed;
}

- (void)setDrawingLineRightAngle:(BOOL)drawingLineRightAngle
{
	_drawingLineRightAngle = drawingLineRightAngle;
	self.drawView.rightAngleLinesOnly = drawingLineRightAngle;
}

- (void)setDrawingLineDiscreteGridSize:(NSUInteger)drawingLineDiscreteGridSize
{
	_drawingLineDiscreteGridSize = drawingLineDiscreteGridSize;
	self.drawingContainer.discreteGridSize = drawingLineDiscreteGridSize;
}

#pragma mark - Undo

- (void)clearAll
{
    [self clearDrawing];
    [self clearText];
}

- (void)clearDrawing
{
    [self.drawView clearDrawing];
}

- (BOOL)canUndoDrawing {
    return [self.drawView canUndo];
}

- (void)undoDrawing
{
	[self.drawView undo];
}

- (void)redoDrawing
{
	[self.drawView redo];
}

- (void)clearText
{
    self.textString = @"";
    [self.textView clearAll];
}

- (void)deleteSelectedLabel {
	[self.textView deleteSelectedLabel];
}

- (void)deSelectLabel {
    [self.textView deselectLabel];
}

#pragma mark - Output UIImage

- (UIImage *)drawOnImage
{
    UIImage *drawImage = [self.drawView drawOnImage];
    return [self.textView drawTextOnImage:drawImage
                          withScaledFrame:[self.imageView frameForImage]
                              scaleFactor:[self.imageView scaleFactorForImage]];
}

#pragma mark - Gestures

- (void)handleTapGesture:(UIGestureRecognizer *)recognizer
{
    if (self.state == JotViewStateText) {
		// a tap during text
		CGPoint touch = [recognizer locationOfTouch:0 inView:self.textView];
        self.lastTapPoint = touch;
		JotLabel *label = [self.textView labelAtPosition:touch];
		if (label) {
			// a tap on a label
			if (label.selected) {
				// a tap on a label already selected
				self.state = JotViewStateEditingText;
			}
			else {
				// a tap on a label not selected
				[self.textView selectLabelAtPosition:touch];
			
				if ([self.delegate respondsToSelector:@selector(jotViewController:didSelectLabel:)]) {
					[self.delegate jotViewController:self didSelectLabel:[label serialize]];
				}
			}
			self.textEditView.textString = label.text;
            self.textEditView.font = label.font;
            self.textEditView.textColor = label.textColor;
		}
		else {
			// a tap on a blank space
            self.textEditView.textString = @"";
			self.state = JotViewStateEditingText;
		}
    }
}

- (void)handlePanGesture:(UIGestureRecognizer *)recognizer
{
    [self.textView handlePanGesture:recognizer];
}

- (void)handlePinchGesture:(UIGestureRecognizer *)recognizer
{
    [self.textView handlePinchOrRotateGesture:recognizer];
}

- (void)handleRotateGesture:(UIGestureRecognizer *)recognizer
{
	[self.textView handlePinchOrRotateGesture:recognizer];
}

#pragma mark - JotDrawingContainer Delegate

- (BOOL)jotDrawingContainerShouldDiscretise {
	return self.state == JotViewStateDrawLines;
}

- (void)jotDrawingContainerTouchBeganAtPoint:(CGPoint)touchPoint
{
    if (self.state == JotViewStateDrawing) {
        [self.drawView drawTouchBeganAtPoint:touchPoint];
        if ([self.delegate respondsToSelector:@selector(drawingBegan)]) {
            [self.delegate drawingBegan];
        }
    }
	else if (self.state == JotViewStateDrawLines) {
		[self.drawView drawLineBeganAtPoint:touchPoint];
    } else if (self.state == JotViewStateEditingText) {
        self.state = JotViewStateText;
    }
}

- (void)jotDrawingContainerTouchMovedToPoint:(CGPoint)touchPoint
{
    if (self.state == JotViewStateDrawing) {
        [self.drawView drawTouchMovedToPoint:touchPoint];
    }
	else if (self.state == JotViewStateDrawLines) {
		[self.drawView drawLineMovedToPoint:touchPoint];
	}
}

- (void)jotDrawingContainerTouchEndedAtPoint:(CGPoint)touchPoint
{
    if (self.state == JotViewStateDrawing) {
        [self.drawView drawTouchEndedAtPoint:touchPoint];
        if ([self.delegate respondsToSelector:@selector(drawingEnded)]) {
            [self.delegate drawingEnded];
        }
    }
	else if (self.state == JotViewStateDrawLines) {
		[self.drawView drawLineEndedAtPoint:touchPoint];
	}
}

#pragma mark - UIGestureRecognizer Delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

#pragma mark - JotTextEditView Delegate

- (void)jotTextEditViewFinishedEditingWithNewTextString:(NSString *)textString
{
    if (self.state == JotViewStateEditingText) {
        self.state = JotViewStateText;
    }
    
    self.textString = textString;
    
    if ([self.delegate respondsToSelector:@selector(jotViewController:isEditingText:)]) {
        [self.delegate jotViewController:self isEditingText:NO];
    }
}

#pragma mark - Orientation

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
	
	self.drawView.alpha = 0;

	[coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
		[self.drawView refreshBitmap];
		[UIView animateWithDuration:0.2f animations:^{
			self.drawView.alpha = 1;
		}];
	}];
}

#pragma mark - Serialization

- (NSDictionary*)serialize {
	NSDictionary *drawView = [self.drawView serialize];
	NSArray *labels = [self.textView serialize];
	return @{kDrawView: drawView,
			 kLabels: labels,
			 kDate: [NSDate date]};
}

- (void)unserialize:(NSDictionary*)dictionary {
	if (dictionary[kDrawView]) {
		[self.drawView unserialize:dictionary[kDrawView]];
	}
	if (dictionary[kLabels]) {
		[self.textView unserialize:dictionary[kLabels]];
	}
}


#pragma mark - JotDrawViewDelegate

- (void)shouldDisableUndo {
    if ([self.delegate respondsToSelector:@selector(shouldDisableUndo)]) {
        [self.delegate shouldDisableUndo];
    }
}

- (void)shouldEnableUndo {
    if ([self.delegate respondsToSelector:@selector(shouldEnableUndo)]) {
        [self.delegate shouldEnableUndo];
    }
}

@end
