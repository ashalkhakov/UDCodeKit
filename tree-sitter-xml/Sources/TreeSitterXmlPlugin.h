/*---------------------------------------------------------------------------------------------
 *  TreeSitterXmlPlugin.h  —  Principal class for the TreeSitterXml bundle.
 *
 *  Conforms to UDExtension: the tree-sitter language factory is provided via
 *  -languageFuncForIdentifier: (no dlsym required).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDExtension.h"
#import "UDXMLLSPInstaller.h"

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterXmlPlugin : NSObject <UDExtension, XMLLSPInstallerDelegate>


@end

NS_ASSUME_NONNULL_END
