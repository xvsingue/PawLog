//
//  AsyncAttachmentThumbnail.swift
//  PawLog
//
//  缩略图异步解码视图：先显示占位，再在后台解码 thumbnailData。
//

import SwiftUI

struct AsyncAttachmentThumbnail: View {
    let data: Data?
    var maxPixelSize: CGFloat = AttachmentStore.maxThumbnailPixelSize

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Theme.Palette.fill
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .clipped()
        .task(id: data) {
            guard let data else {
                image = nil
                return
            }
            image = await AttachmentThumbnailLoader.load(data: data, maxPixelSize: maxPixelSize)
        }
    }
}

#Preview("AsyncAttachmentThumbnail") {
    AsyncAttachmentThumbnail(data: nil)
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.input))
        .padding()
        .background(Theme.Palette.background)
}
