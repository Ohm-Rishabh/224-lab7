// Code generated by protoc-gen-go. DO NOT EDIT.
// versions:
// 	protoc-gen-go v1.36.6
// 	protoc        v5.29.3
// source: proto/storage.proto

package proto

import (
	protoreflect "google.golang.org/protobuf/reflect/protoreflect"
	protoimpl "google.golang.org/protobuf/runtime/protoimpl"
	reflect "reflect"
	sync "sync"
	unsafe "unsafe"
)

const (
	// Verify that this generated code is sufficiently up-to-date.
	_ = protoimpl.EnforceVersion(20 - protoimpl.MinVersion)
	// Verify that runtime/protoimpl is sufficiently up-to-date.
	_ = protoimpl.EnforceVersion(protoimpl.MaxVersion - 20)
)

type WriteFileRequest struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	VideoId       string                 `protobuf:"bytes,1,opt,name=video_id,json=videoId,proto3" json:"video_id,omitempty"`
	Filename      string                 `protobuf:"bytes,2,opt,name=filename,proto3" json:"filename,omitempty"`
	Data          []byte                 `protobuf:"bytes,3,opt,name=data,proto3" json:"data,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *WriteFileRequest) Reset() {
	*x = WriteFileRequest{}
	mi := &file_proto_storage_proto_msgTypes[0]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *WriteFileRequest) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*WriteFileRequest) ProtoMessage() {}

func (x *WriteFileRequest) ProtoReflect() protoreflect.Message {
	mi := &file_proto_storage_proto_msgTypes[0]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use WriteFileRequest.ProtoReflect.Descriptor instead.
func (*WriteFileRequest) Descriptor() ([]byte, []int) {
	return file_proto_storage_proto_rawDescGZIP(), []int{0}
}

func (x *WriteFileRequest) GetVideoId() string {
	if x != nil {
		return x.VideoId
	}
	return ""
}

func (x *WriteFileRequest) GetFilename() string {
	if x != nil {
		return x.Filename
	}
	return ""
}

func (x *WriteFileRequest) GetData() []byte {
	if x != nil {
		return x.Data
	}
	return nil
}

type WriteFileResponse struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *WriteFileResponse) Reset() {
	*x = WriteFileResponse{}
	mi := &file_proto_storage_proto_msgTypes[1]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *WriteFileResponse) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*WriteFileResponse) ProtoMessage() {}

func (x *WriteFileResponse) ProtoReflect() protoreflect.Message {
	mi := &file_proto_storage_proto_msgTypes[1]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use WriteFileResponse.ProtoReflect.Descriptor instead.
func (*WriteFileResponse) Descriptor() ([]byte, []int) {
	return file_proto_storage_proto_rawDescGZIP(), []int{1}
}

type ReadFileRequest struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	VideoId       string                 `protobuf:"bytes,1,opt,name=video_id,json=videoId,proto3" json:"video_id,omitempty"`
	Filename      string                 `protobuf:"bytes,2,opt,name=filename,proto3" json:"filename,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *ReadFileRequest) Reset() {
	*x = ReadFileRequest{}
	mi := &file_proto_storage_proto_msgTypes[2]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *ReadFileRequest) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ReadFileRequest) ProtoMessage() {}

func (x *ReadFileRequest) ProtoReflect() protoreflect.Message {
	mi := &file_proto_storage_proto_msgTypes[2]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use ReadFileRequest.ProtoReflect.Descriptor instead.
func (*ReadFileRequest) Descriptor() ([]byte, []int) {
	return file_proto_storage_proto_rawDescGZIP(), []int{2}
}

func (x *ReadFileRequest) GetVideoId() string {
	if x != nil {
		return x.VideoId
	}
	return ""
}

func (x *ReadFileRequest) GetFilename() string {
	if x != nil {
		return x.Filename
	}
	return ""
}

type ReadFileResponse struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Data          []byte                 `protobuf:"bytes,1,opt,name=data,proto3" json:"data,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *ReadFileResponse) Reset() {
	*x = ReadFileResponse{}
	mi := &file_proto_storage_proto_msgTypes[3]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *ReadFileResponse) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ReadFileResponse) ProtoMessage() {}

func (x *ReadFileResponse) ProtoReflect() protoreflect.Message {
	mi := &file_proto_storage_proto_msgTypes[3]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use ReadFileResponse.ProtoReflect.Descriptor instead.
func (*ReadFileResponse) Descriptor() ([]byte, []int) {
	return file_proto_storage_proto_rawDescGZIP(), []int{3}
}

func (x *ReadFileResponse) GetData() []byte {
	if x != nil {
		return x.Data
	}
	return nil
}

type DeleteFileRequest struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	VideoId       string                 `protobuf:"bytes,1,opt,name=video_id,json=videoId,proto3" json:"video_id,omitempty"`
	Filename      string                 `protobuf:"bytes,2,opt,name=filename,proto3" json:"filename,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *DeleteFileRequest) Reset() {
	*x = DeleteFileRequest{}
	mi := &file_proto_storage_proto_msgTypes[4]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *DeleteFileRequest) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*DeleteFileRequest) ProtoMessage() {}

func (x *DeleteFileRequest) ProtoReflect() protoreflect.Message {
	mi := &file_proto_storage_proto_msgTypes[4]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use DeleteFileRequest.ProtoReflect.Descriptor instead.
func (*DeleteFileRequest) Descriptor() ([]byte, []int) {
	return file_proto_storage_proto_rawDescGZIP(), []int{4}
}

func (x *DeleteFileRequest) GetVideoId() string {
	if x != nil {
		return x.VideoId
	}
	return ""
}

func (x *DeleteFileRequest) GetFilename() string {
	if x != nil {
		return x.Filename
	}
	return ""
}

type DeleteFileResponse struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *DeleteFileResponse) Reset() {
	*x = DeleteFileResponse{}
	mi := &file_proto_storage_proto_msgTypes[5]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *DeleteFileResponse) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*DeleteFileResponse) ProtoMessage() {}

func (x *DeleteFileResponse) ProtoReflect() protoreflect.Message {
	mi := &file_proto_storage_proto_msgTypes[5]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use DeleteFileResponse.ProtoReflect.Descriptor instead.
func (*DeleteFileResponse) Descriptor() ([]byte, []int) {
	return file_proto_storage_proto_rawDescGZIP(), []int{5}
}

type ListFilesRequest struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *ListFilesRequest) Reset() {
	*x = ListFilesRequest{}
	mi := &file_proto_storage_proto_msgTypes[6]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *ListFilesRequest) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ListFilesRequest) ProtoMessage() {}

func (x *ListFilesRequest) ProtoReflect() protoreflect.Message {
	mi := &file_proto_storage_proto_msgTypes[6]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use ListFilesRequest.ProtoReflect.Descriptor instead.
func (*ListFilesRequest) Descriptor() ([]byte, []int) {
	return file_proto_storage_proto_rawDescGZIP(), []int{6}
}

type ListFilesResponse struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Paths         []string               `protobuf:"bytes,1,rep,name=paths,proto3" json:"paths,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *ListFilesResponse) Reset() {
	*x = ListFilesResponse{}
	mi := &file_proto_storage_proto_msgTypes[7]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *ListFilesResponse) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ListFilesResponse) ProtoMessage() {}

func (x *ListFilesResponse) ProtoReflect() protoreflect.Message {
	mi := &file_proto_storage_proto_msgTypes[7]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use ListFilesResponse.ProtoReflect.Descriptor instead.
func (*ListFilesResponse) Descriptor() ([]byte, []int) {
	return file_proto_storage_proto_rawDescGZIP(), []int{7}
}

func (x *ListFilesResponse) GetPaths() []string {
	if x != nil {
		return x.Paths
	}
	return nil
}

var File_proto_storage_proto protoreflect.FileDescriptor

const file_proto_storage_proto_rawDesc = "" +
	"\n" +
	"\x13proto/storage.proto\x12\n" +
	"tritontube\"]\n" +
	"\x10WriteFileRequest\x12\x19\n" +
	"\bvideo_id\x18\x01 \x01(\tR\avideoId\x12\x1a\n" +
	"\bfilename\x18\x02 \x01(\tR\bfilename\x12\x12\n" +
	"\x04data\x18\x03 \x01(\fR\x04data\"\x13\n" +
	"\x11WriteFileResponse\"H\n" +
	"\x0fReadFileRequest\x12\x19\n" +
	"\bvideo_id\x18\x01 \x01(\tR\avideoId\x12\x1a\n" +
	"\bfilename\x18\x02 \x01(\tR\bfilename\"&\n" +
	"\x10ReadFileResponse\x12\x12\n" +
	"\x04data\x18\x01 \x01(\fR\x04data\"J\n" +
	"\x11DeleteFileRequest\x12\x19\n" +
	"\bvideo_id\x18\x01 \x01(\tR\avideoId\x12\x1a\n" +
	"\bfilename\x18\x02 \x01(\tR\bfilename\"\x14\n" +
	"\x12DeleteFileResponse\"\x12\n" +
	"\x10ListFilesRequest\")\n" +
	"\x11ListFilesResponse\x12\x14\n" +
	"\x05paths\x18\x01 \x03(\tR\x05paths2\xbd\x02\n" +
	"\x13VideoStorageService\x12H\n" +
	"\tWriteFile\x12\x1c.tritontube.WriteFileRequest\x1a\x1d.tritontube.WriteFileResponse\x12E\n" +
	"\bReadFile\x12\x1b.tritontube.ReadFileRequest\x1a\x1c.tritontube.ReadFileResponse\x12K\n" +
	"\n" +
	"DeleteFile\x12\x1d.tritontube.DeleteFileRequest\x1a\x1e.tritontube.DeleteFileResponse\x12H\n" +
	"\tListFiles\x12\x1c.tritontube.ListFilesRequest\x1a\x1d.tritontube.ListFilesResponseB\x10Z\x0einternal/protob\x06proto3"

var (
	file_proto_storage_proto_rawDescOnce sync.Once
	file_proto_storage_proto_rawDescData []byte
)

func file_proto_storage_proto_rawDescGZIP() []byte {
	file_proto_storage_proto_rawDescOnce.Do(func() {
		file_proto_storage_proto_rawDescData = protoimpl.X.CompressGZIP(unsafe.Slice(unsafe.StringData(file_proto_storage_proto_rawDesc), len(file_proto_storage_proto_rawDesc)))
	})
	return file_proto_storage_proto_rawDescData
}

var file_proto_storage_proto_msgTypes = make([]protoimpl.MessageInfo, 8)
var file_proto_storage_proto_goTypes = []any{
	(*WriteFileRequest)(nil),   // 0: tritontube.WriteFileRequest
	(*WriteFileResponse)(nil),  // 1: tritontube.WriteFileResponse
	(*ReadFileRequest)(nil),    // 2: tritontube.ReadFileRequest
	(*ReadFileResponse)(nil),   // 3: tritontube.ReadFileResponse
	(*DeleteFileRequest)(nil),  // 4: tritontube.DeleteFileRequest
	(*DeleteFileResponse)(nil), // 5: tritontube.DeleteFileResponse
	(*ListFilesRequest)(nil),   // 6: tritontube.ListFilesRequest
	(*ListFilesResponse)(nil),  // 7: tritontube.ListFilesResponse
}
var file_proto_storage_proto_depIdxs = []int32{
	0, // 0: tritontube.VideoStorageService.WriteFile:input_type -> tritontube.WriteFileRequest
	2, // 1: tritontube.VideoStorageService.ReadFile:input_type -> tritontube.ReadFileRequest
	4, // 2: tritontube.VideoStorageService.DeleteFile:input_type -> tritontube.DeleteFileRequest
	6, // 3: tritontube.VideoStorageService.ListFiles:input_type -> tritontube.ListFilesRequest
	1, // 4: tritontube.VideoStorageService.WriteFile:output_type -> tritontube.WriteFileResponse
	3, // 5: tritontube.VideoStorageService.ReadFile:output_type -> tritontube.ReadFileResponse
	5, // 6: tritontube.VideoStorageService.DeleteFile:output_type -> tritontube.DeleteFileResponse
	7, // 7: tritontube.VideoStorageService.ListFiles:output_type -> tritontube.ListFilesResponse
	4, // [4:8] is the sub-list for method output_type
	0, // [0:4] is the sub-list for method input_type
	0, // [0:0] is the sub-list for extension type_name
	0, // [0:0] is the sub-list for extension extendee
	0, // [0:0] is the sub-list for field type_name
}

func init() { file_proto_storage_proto_init() }
func file_proto_storage_proto_init() {
	if File_proto_storage_proto != nil {
		return
	}
	type x struct{}
	out := protoimpl.TypeBuilder{
		File: protoimpl.DescBuilder{
			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
			RawDescriptor: unsafe.Slice(unsafe.StringData(file_proto_storage_proto_rawDesc), len(file_proto_storage_proto_rawDesc)),
			NumEnums:      0,
			NumMessages:   8,
			NumExtensions: 0,
			NumServices:   1,
		},
		GoTypes:           file_proto_storage_proto_goTypes,
		DependencyIndexes: file_proto_storage_proto_depIdxs,
		MessageInfos:      file_proto_storage_proto_msgTypes,
	}.Build()
	File_proto_storage_proto = out.File
	file_proto_storage_proto_goTypes = nil
	file_proto_storage_proto_depIdxs = nil
}
