import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/note.dart';
import '../../models/folder.dart';
import '../../services/note_storage_service.dart';
import '../../services/git_service.dart';
import '../../services/settings_service.dart';

// Events
abstract class NotesEvent extends Equatable {
  const NotesEvent();

  @override
  List<Object?> get props => [];
}

class LoadNotes extends NotesEvent {
  final String? folderPath;
  const LoadNotes({this.folderPath});

  @override
  List<Object?> get props => [folderPath];
}

class CreateNote extends NotesEvent {
  final String title;
  final String? folderPath;
  final String content;
  const CreateNote({
    required this.title,
    this.folderPath,
    this.content = '',
  });

  @override
  List<Object?> get props => [title, folderPath, content];
}

class SelectNote extends NotesEvent {
  final Note note;
  const SelectNote(this.note);

  @override
  List<Object?> get props => [note];
}

class UpdateNote extends NotesEvent {
  final Note note;
  const UpdateNote(this.note);

  @override
  List<Object?> get props => [note];
}

class DeleteNote extends NotesEvent {
  final String filePath;
  const DeleteNote(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class SearchNotes extends NotesEvent {
  final String query;
  const SearchNotes(this.query);

  @override
  List<Object?> get props => [query];
}

class SyncWithGit extends NotesEvent {
  const SyncWithGit();
}

class MarkUnsynced extends NotesEvent {
  const MarkUnsynced();
}

class ArchiveNote extends NotesEvent {
  final String filePath;
  const ArchiveNote(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class UnarchiveNote extends NotesEvent {
  final String filePath;
  const UnarchiveNote(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

// States
abstract class NotesState extends Equatable {
  const NotesState();

  @override
  List<Object?> get props => [];
}

class NotesInitial extends NotesState {}

class NotesLoading extends NotesState {}

class NotesLoaded extends NotesState {
  final List<Note> notes;
  final List<Folder> folders;
  final Note? selectedNote;
  final String? currentFolderPath;
  final String? searchQuery;
  final bool isSyncing;
  final String? syncError;
  final bool hasUnsyncedChanges;

  const NotesLoaded({
    required this.notes,
    required this.folders,
    this.selectedNote,
    this.currentFolderPath,
    this.searchQuery,
    this.isSyncing = false,
    this.syncError,
    this.hasUnsyncedChanges = false,
  });

  NotesLoaded copyWith({
    List<Note>? notes,
    List<Folder>? folders,
    Note? selectedNote,
    String? currentFolderPath,
    String? searchQuery,
    bool? isSyncing,
    String? syncError,
    bool? hasUnsyncedChanges,
    bool clearSelectedNote = false,
    bool clearSyncError = false,
  }) {
    return NotesLoaded(
      notes: notes ?? this.notes,
      folders: folders ?? this.folders,
      selectedNote: clearSelectedNote ? null : (selectedNote ?? this.selectedNote),
      currentFolderPath: currentFolderPath ?? this.currentFolderPath,
      searchQuery: searchQuery ?? this.searchQuery,
      isSyncing: isSyncing ?? this.isSyncing,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
      hasUnsyncedChanges: hasUnsyncedChanges ?? this.hasUnsyncedChanges,
    );
  }

  @override
  List<Object?> get props => [
        notes,
        folders,
        selectedNote,
        currentFolderPath,
        searchQuery,
        isSyncing,
        syncError,
        hasUnsyncedChanges,
      ];
}

class NotesError extends NotesState {
  final String message;
  const NotesError(this.message);

  @override
  List<Object?> get props => [message];
}

// Bloc
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final NoteStorageService _storageService;
  final GitService _gitService;
  final SettingsService _settingsService;

  NotesBloc({
    required NoteStorageService storageService,
    required GitService gitService,
    required SettingsService settingsService,
  })  : _storageService = storageService,
        _gitService = gitService,
        _settingsService = settingsService,
        super(NotesInitial()) {
    on<LoadNotes>(_onLoadNotes);
    on<CreateNote>(_onCreateNote);
    on<SelectNote>(_onSelectNote);
    on<UpdateNote>(_onUpdateNote);
    on<DeleteNote>(_onDeleteNote);
    on<SearchNotes>(_onSearchNotes);
    on<SyncWithGit>(_onSyncWithGit);
    on<MarkUnsynced>(_onMarkUnsynced);
    on<ArchiveNote>(_onArchiveNote);
    on<UnarchiveNote>(_onUnarchiveNote);
  }

  Future<void> _onLoadNotes(
    LoadNotes event,
    Emitter<NotesState> emit,
  ) async {
    emit(NotesLoading());
    try {
      final notes = event.folderPath != null
          ? await _storageService.getNotesInFolder(event.folderPath!)
          : await _storageService.getAllNotes();
      final folders = await _storageService.getAllFolders();
      emit(NotesLoaded(
        notes: notes,
        folders: folders,
        currentFolderPath: event.folderPath,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onCreateNote(
    CreateNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      final note = await _storageService.createNote(
        title: event.title,
        folderPath: event.folderPath,
        content: event.content,
      );

      final updatedNotes = [...currentState.notes, note];
      emit(currentState.copyWith(
        notes: updatedNotes,
        selectedNote: note,
        hasUnsyncedChanges: true,
      ));

      // 如果配置了 Git，自动触发 push
      final config = _settingsService.gitConfig;
      if (config != null && config.localPath.isNotEmpty) {
        // 异步执行 Git 操作，不阻塞 UI
        _autoPushToGit();
      }
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  /// 自动推送到 Git（后台执行）
  Future<void> _autoPushToGit() async {
    try {
      final config = _settingsService.gitConfig;
      if (config == null || config.localPath.isEmpty) return;

      await _gitService.initialize();
      
      // 添加所有更改
      _gitService.add(config.localPath, '.');
      
      // 提交
      _gitService.commit(
        repoPath: config.localPath,
        message: '自动提交: ${DateTime.now().toString().substring(0, 19)}',
        authorName: config.username ?? 'ObsidianGit',
        authorEmail: config.email ?? 'obsidian-git@local',
      );
      
      // 推送
      await _gitService.push(
        config: config,
        localPath: config.localPath,
      );
      
      print('自动推送成功');
    } catch (e) {
      print('自动推送失败: $e');
    }
  }

  Future<void> _onSelectNote(
    SelectNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    final note = await _storageService.getNote(event.note.filePath);
    emit(currentState.copyWith(selectedNote: note ?? event.note));
  }

  Future<void> _onUpdateNote(
    UpdateNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      await _storageService.saveNote(event.note);

      final updatedNotes = currentState.notes.map((n) {
        return n.filePath == event.note.filePath ? event.note : n;
      }).toList();

      emit(currentState.copyWith(
        notes: updatedNotes,
        selectedNote: event.note,
        hasUnsyncedChanges: true,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onDeleteNote(
    DeleteNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      await _storageService.deleteNote(event.filePath);

      final updatedNotes = currentState.notes
          .where((n) => n.filePath != event.filePath)
          .toList();

      emit(currentState.copyWith(
        notes: updatedNotes,
        clearSelectedNote: currentState.selectedNote?.filePath == event.filePath,
        hasUnsyncedChanges: true,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onSearchNotes(
    SearchNotes event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      final notes = event.query.isEmpty
          ? await _storageService.getAllNotes()
          : await _storageService.searchNotes(event.query);

      emit(currentState.copyWith(
        notes: notes,
        searchQuery: event.query.isEmpty ? null : event.query,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onMarkUnsynced(
    MarkUnsynced event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    emit(currentState.copyWith(hasUnsyncedChanges: true));
  }

  Future<void> _onArchiveNote(
    ArchiveNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      // 调用存储服务归档笔记
      final archivedNote = await _storageService.archiveNote(event.filePath);
      if (archivedNote != null) {
        // 重新加载笔记列表
        final notes = await _storageService.getAllNotes();
        emit(currentState.copyWith(
          notes: notes,
          selectedNote: currentState.selectedNote?.filePath == event.filePath 
              ? archivedNote 
              : currentState.selectedNote,
        ));
      }
    } catch (e) {
      print('归档笔记失败: $e');
    }
  }

  Future<void> _onUnarchiveNote(
    UnarchiveNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      // 调用存储服务取消归档
      final unarchivedNote = await _storageService.unarchiveNote(event.filePath);
      if (unarchivedNote != null) {
        // 重新加载笔记列表
        final notes = await _storageService.getAllNotes();
        emit(currentState.copyWith(
          notes: notes,
          selectedNote: currentState.selectedNote?.filePath == event.filePath 
              ? unarchivedNote 
              : currentState.selectedNote,
        ));
      }
    } catch (e) {
      print('取消归档失败: $e');
    }
  }

  Future<void> _onSyncWithGit(
    SyncWithGit event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    emit(currentState.copyWith(
      isSyncing: true,
      clearSyncError: true,
    ));

    try {
      // 从 SettingsService 读取配置
      final config = _settingsService.gitConfig;
      if (config == null || config.localPath.isEmpty) {
        emit(currentState.copyWith(
          isSyncing: false,
          syncError: '未配置 Git 仓库',
        ));
        return;
      }

      // 1. 添加所有更改
      _gitService.add(config.localPath, '.');

      // 2. 提交到本地（如果有变更）
      try {
        _gitService.commit(
          repoPath: config.localPath,
          message: 'Sync from Obsidian Git at ${DateTime.now()}',
          authorName: config.username ?? 'Obsidian Git User',
          authorEmail: config.email ?? 'user@example.com',
        );
      } catch (e) {
        // 没有变更需要提交，继续
        print('No changes to commit: $e');
      }

      // 3. 拉取远程更新
      try {
        await _gitService.pull(
          config: config,
          localPath: config.localPath,
        );
      } catch (e) {
        emit(currentState.copyWith(
          isSyncing: false,
          syncError: '拉取失败: $e',
        ));
        return;
      }

      // 4. 推送到远程
      try {
        await _gitService.push(
          config: config,
          localPath: config.localPath,
        );
      } catch (e) {
        emit(currentState.copyWith(
          isSyncing: false,
          syncError: '推送失败: $e',
        ));
        return;
      }

      // 5. 重新加载笔记
      final notes = await _storageService.getAllNotes();
      emit(currentState.copyWith(
        notes: notes,
        isSyncing: false,
        hasUnsyncedChanges: false,
      ));
    } catch (e) {
      emit(currentState.copyWith(
        isSyncing: false,
        syncError: e.toString(),
      ));
    }
  }
}
