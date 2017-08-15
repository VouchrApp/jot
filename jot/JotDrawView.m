//
//  JotDrawView.m
//  jot
//
//  Created by Laura Skelton on 4/30/15.
//
//

#import "JotDrawView.h"
#import "JotTouchPoint.h"
#import "JotTouchBezier.h"
#import "JotTouchLine.h"
#import "UIImage+Jot.h"
#import "UIImageView+ImageFrame.h"

CGFloat const kJotVelocityFilterWeight = 0.9f;
CGFloat const kJotInitialVelocity = 220.f;
CGFloat const kJotRelativeMinStrokeWidth = 0.4f;

NSString const* kObjects = @"Objects";
NSString const* kUndoArray = @"UndoArray";

@interface JotDrawView ()

@property (nonatomic, strong) UIImage *cachedImage;
@property (nonatomic, weak) UIImageView *imageView;

@property (nonatomic, strong) NSMutableArray <JotTouchObject*> *pathsArray;
@property (nonatomic, strong) NSMutableArray <NSNumber*> *undoArray;
@property (nonatomic, assign) NSInteger undoIndex;

@property (nonatomic, strong) NSMutableArray <JotTouchPoint*> *pointsArray;
@property (nonatomic, assign) NSUInteger pointsCounter;
@property (nonatomic, assign) CGFloat lastVelocity;
@property (nonatomic, assign) CGFloat lastWidth;
@property (nonatomic, assign) CGFloat initialVelocity;

@end

@implementation JotDrawView

- (instancetype)init
{
    if ((self = [super init])) {
        
        self.backgroundColor = [UIColor clearColor];
        
        _strokeWidth = 10.f;
        _strokeColor = [UIColor blackColor];
        
        _pathsArray = [NSMutableArray array];
		_undoArray  = [NSMutableArray arrayWithObject:@0];
		_undoIndex  = 0;
        
        _constantStrokeWidth = NO;
        
        _pointsArray = [NSMutableArray array];
        _initialVelocity = kJotInitialVelocity;
        _lastVelocity = _initialVelocity;
        _lastWidth = _strokeWidth;
        
        self.userInteractionEnabled = NO;
    }
    
    return self;
}

- (void)setupForImageView:(UIImageView *)imageView
{
    self.imageView = imageView;
}

#pragma mark - Undo

- (void)clearDrawing
{
    self.cachedImage = nil;
    
    [self.pathsArray removeAllObjects];
	[self.undoArray removeObjectsInRange:NSMakeRange(1, self.undoArray.count-1)];
	self.undoIndex = 0;
	
    self.pointsCounter = 0;
    [self.pointsArray removeAllObjects];
    self.lastVelocity = self.initialVelocity;
    self.lastWidth = self.strokeWidth;
    
    [UIView transitionWithView:self duration:0.2f
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
                        [self setNeedsDisplay];
                    }
                    completion:nil];
}

- (BOOL)canUndo {
    return self.undoIndex > 0;
}

- (void)undo {
	if (self.undoIndex > 0) {
		self.undoIndex -= 1;
		[self refreshBitmap];
        if (self.undoIndex == 0) {
            if ([self.delegate respondsToSelector:@selector(shouldDisableUndo)]) {
                [self.delegate shouldDisableUndo];
            }
        }
    }
}

- (void)redo {
	if (self.undoIndex < self.undoArray.count-1) {
		self.undoIndex += 1;
		[self refreshBitmap];
	}
}

- (void)undoAddState {
	[self.undoArray addObject:@(self.pathsArray.count)];
	self.undoIndex = self.undoArray.count-1;
    if ([self.delegate respondsToSelector:@selector(shouldEnableUndo)]) {
        [self.delegate shouldEnableUndo];
    }
}

- (void)clearRedo {
	// if undo happened, remove everything after undo state
	if (self.undoIndex < self.undoArray.count-1) {
		NSUInteger pathArrayFinalCount = [self.undoArray[self.undoIndex] integerValue];
		[self.pathsArray removeObjectsInRange:NSMakeRange(pathArrayFinalCount, self.pathsArray.count - pathArrayFinalCount)];
		NSUInteger undoFinalCount = self.undoIndex+1;
		[self.undoArray removeObjectsInRange:NSMakeRange(undoFinalCount, self.undoArray.count - undoFinalCount)];
	}
}

- (void)logUndoStatus {
	NSLog(@"Path array count: %d", (int)self.pathsArray.count);
	NSLog(@"Undo array [%@] - cursor: %d", [self.undoArray componentsJoinedByString:@" - "], (int)self.undoIndex);
}

#pragma mark - Properties

- (void)setConstantStrokeWidth:(BOOL)constantStrokeWidth
{
    if (_constantStrokeWidth != constantStrokeWidth) {
        _constantStrokeWidth = constantStrokeWidth;
        [self.pointsArray removeAllObjects];
        self.pointsCounter = 0;
    }
}

#pragma mark - Free hand draw Touches

- (void)drawTouchBeganAtPoint:(CGPoint)point
{
	// Clear further redo if any
	[self clearRedo];
	
    self.lastVelocity = self.initialVelocity;
    self.lastWidth = self.strokeWidth;
    self.pointsCounter = 0;
    [self.pointsArray removeAllObjects];
	JotTouchPoint *touchPoint = [JotTouchPoint withPoint:point
                                             scaleFactor:[self.imageView scaleFactorForImage]];
    [self.pointsArray addObject:touchPoint];
	
	touchPoint.strokeWidth = self.strokeWidth;
	touchPoint.strokeColor = self.strokeColor;
	[self.pathsArray addObject:touchPoint];
	
	// Adds an undo state
	[self undoAddState];
	// And refresh drawing
	[self setNeedsDisplayInRect:touchPoint.rect];
}

- (void)drawTouchMovedToPoint:(CGPoint)touchPoint
{
    self.pointsCounter += 1;
    [self.pointsArray addObject:[JotTouchPoint withPoint:touchPoint
                                             scaleFactor:[self.imageView scaleFactorForImage]]];
    
    if (self.pointsCounter == 4) {
        
        self.pointsArray[3] = [JotTouchPoint withPoint:CGPointMake(([self.pointsArray[2] CGPointValue].x + [self.pointsArray[4] CGPointValue].x)/2.f,
                                                                   ([self.pointsArray[2] CGPointValue].y + [self.pointsArray[4] CGPointValue].y)/2.f)
                                           scaleFactor:[self.imageView scaleFactorForImage]];
		
		JotTouchBezier *bezierPath = [JotTouchBezier withStartPoint:[self.pointsArray[0] CGPointValue]
														   endPoint:[self.pointsArray[3] CGPointValue]
													  controlPoint1:[self.pointsArray[1] CGPointValue]
													  controlPoint2:[self.pointsArray[2] CGPointValue]
                                                        scaleFactor:[self.imageView scaleFactorForImage]];
		bezierPath.strokeColor = self.strokeColor;
		bezierPath.constantWidth = self.constantStrokeWidth;
		
        if (bezierPath.constantWidth) {
            bezierPath.startWidth = self.strokeWidth;
            bezierPath.endWidth = self.strokeWidth;
        } else {
            CGFloat velocity = [self.pointsArray[3] velocityFromPoint:self.pointsArray[0]];
            velocity = (kJotVelocityFilterWeight * velocity) + ((1.f - kJotVelocityFilterWeight) * self.lastVelocity);
            
            CGFloat strokeWidth = [self strokeWidthForVelocity:velocity];
            
            bezierPath.startWidth = self.lastWidth;
            bezierPath.endWidth = strokeWidth;
            
            self.lastWidth = strokeWidth;
            self.lastVelocity = velocity;
        }
		[self.pathsArray addObject:bezierPath];
		self.undoArray[self.undoArray.count-1] = @(self.pathsArray.count);
		
        self.pointsArray[0] = self.pointsArray[3];
        self.pointsArray[1] = self.pointsArray[4];
        
		[self setNeedsDisplayInRect:bezierPath.rect];
		
        [self.pointsArray removeLastObject];
        [self.pointsArray removeLastObject];
        [self.pointsArray removeLastObject];
        self.pointsCounter = 1;
    }
}

- (void)drawTouchEndedAtPoint:(CGPoint)point
{
    self.lastVelocity = self.initialVelocity;
    self.lastWidth = self.strokeWidth;
}

#pragma mark - Line draw Touches

- (void)drawLineBeganAtPoint:(CGPoint)point {
	// Clear further redo if any
	[self clearRedo];
	
	JotTouchLine *touchLine = [JotTouchLine withStartPoint:point];
	touchLine.strokeWidth = self.strokeWidth;
	touchLine.strokeColor = self.strokeColor;
	touchLine.dashed	  = self.dashedLine;
	[self.pathsArray addObject:touchLine];
	
	// Adds an undo state
	[self undoAddState];
	// And refresh drawing
	[self setNeedsDisplayInRect:touchLine.rect];
}

- (void)drawLineMovedToPoint:(CGPoint)point {
	JotTouchObject *touchLine = [self.pathsArray lastObject];
	if (touchLine && [touchLine isKindOfClass:JotTouchLine.class]) {
		CGRect oldRect = touchLine.rect;
		((JotTouchLine *)touchLine).pointB = point;
		[self setNeedsDisplayInRect:CGRectUnion(oldRect, touchLine.rect)];
	}
}

- (void)drawLineEndedAtPoint:(CGPoint)point {
	[self drawLineMovedToPoint:point];
}

#pragma mark - Drawing

- (void)refreshBitmap {
	UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, [UIScreen mainScreen].scale);
	
	[self setNeedsDisplay];
	
	self.cachedImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
}

- (void)drawRect:(CGRect)rect
{
	__block int drawCalls = 0;

	NSUInteger pathArrayUndoedCount = [self.undoArray[self.undoIndex] integerValue];
	for (int i=0; i < pathArrayUndoedCount; i++) {
		JotTouchObject *touchObject = self.pathsArray[i];
		if (CGRectIntersectsRect(rect, touchObject.rect)) {
			[touchObject jotDrawWithScaling:NO];
			drawCalls++;
		}
	}
}

- (CGFloat)strokeWidthForVelocity:(CGFloat)velocity
{
    return self.strokeWidth - ((self.strokeWidth * (1.f - kJotRelativeMinStrokeWidth)) / (1.f + (CGFloat)pow((double)M_E, (double)(-((velocity - self.initialVelocity) / self.initialVelocity)))));
}

#pragma mark - Image Rendering

- (UIImage *)renderDrawingWithSize:(CGSize)size
{
    CGFloat scale = size.width / CGRectGetWidth(self.bounds);
    return [self drawAllPathsImageScale:scale
						backgroundImage:nil];
}

- (UIImage *)drawOnImage
{
	return [self drawAllPathsImageScale:1.f
                        backgroundImage:self.imageView.image];
}

- (UIImage *)drawOnImage:(UIImage *)image
{
    return [self drawAllPathsImageScale:[UIScreen mainScreen].scale
                        backgroundImage:image];
}

- (UIImage *)drawAllPathsImageScale:(CGFloat)scale backgroundImage:(UIImage *)backgroundImage
{
    CGSize finalImageSize = CGSizeMake(backgroundImage.size.width,
                                       backgroundImage.size.height);
    UIGraphicsBeginImageContextWithOptions(finalImageSize, NO, scale);
    
    [backgroundImage drawInRect:CGRectMake(0,
                                           0,
                                           backgroundImage.size.width,
                                           backgroundImage.size.height)];
	
    [self drawAllPaths];
    
    UIImage *drawnImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return drawnImage;
}

- (void)drawAllPaths
{
	NSUInteger pathArrayUndoedCount = [self.undoArray[self.undoIndex] integerValue];
	for (int i=0; i < pathArrayUndoedCount; i++) {
		JotTouchObject *touchObject = self.pathsArray[i];
		[touchObject jotDrawWithScaling:YES];
	}
}

#pragma mark - Serialization

- (NSDictionary*)serialize {
	NSMutableArray *objects = [NSMutableArray new];
	// only save the not undoed objects
	NSUInteger pathArrayUndoedCount = [self.undoArray[self.undoIndex] integerValue];
	for (int i=0; i < pathArrayUndoedCount; i++) {
		JotTouchObject *touchObject = self.pathsArray[i];
		[objects addObject:[touchObject serialize]];
	}
	return @{kObjects: objects,
			 kUndoArray: [self.undoArray subarrayWithRange:NSMakeRange(0, self.undoIndex+1)]};
}

- (void)unserialize:(NSDictionary*)dictionary {
	if (dictionary[kObjects]) {
		NSArray *objects = dictionary[kObjects];
		for (NSDictionary *objectDic in objects) {
			JotTouchObject *touchObject = [JotTouchObject fromSerialized:objectDic];
			[self.pathsArray addObject:touchObject];
		}
		if (dictionary[kUndoArray]) {
			self.undoArray = [dictionary[kUndoArray] mutableCopy];
			self.undoIndex = self.undoArray.count -1;
		}
		else {
			[self undoAddState];
		}
	}
}

@end
