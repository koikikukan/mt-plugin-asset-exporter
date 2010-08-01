package AssetExporter::Theme;
use strict;

use MT;
use MT::Asset;
use Data::Dumper;

sub condition {
    my ( $blog ) = @_;
    my $asset = MT->model('asset')->load({ blog_id => $blog->id, class => '*' }, { limit => 1 });
    return defined $asset ? 1 : 0;
}

sub template {
    my $app = shift;
    my ( $blog, $saved ) = @_;

    my @assets = MT->model('asset')->load({
        blog_id => $blog->id,
        class => '*'
    });
    return unless scalar @assets;
    my @list;
    my %checked_ids;
    if ( $saved ) {
        %checked_ids = map { $_ => 1 } @{ $saved->{plugin_default_assets_export_ids} };
    }
    for my $asset ( @assets ) {
        push @list, {
            asset_label  => $asset->label,
            asset_id     => $asset->id,
            checked      => $saved ? $checked_ids{ $asset->id } : 1,
        };
    }
    my %param = ( assets => \@list );

    my $plugin = MT->component('AssetExporter');
    return $plugin->load_tmpl('export_asset.tmpl', \%param);
}

sub export {
    my ( $app, $blog, $settings ) = @_;
    my @assets;
    if ( defined $settings ) {
        my @ids = $settings->{plugin_default_assets_export_ids};
        @assets = MT->model('asset')->load({ id => \@ids });
    } else {
        @assets = MT->model('asset')->load({ blog_id => $blog->id, class => '*' });
    }
    return unless scalar @assets;

    my $data = {};
    for my $asset ( @assets ) {
        my $hash = {
            label => $asset->label,
            description => $asset->description,
            class => $asset->class,
            mime_type => $asset->mime_type,
            created_on => $asset->created_on,
            created_by => $asset->created_by,
            modified_on => $asset->modified_on,
            modified_by => $asset->modified_by,
            file_ext => $asset->file_ext,
            file_name => $asset->file_name,
            file_path => $asset->file_path,
            url => $asset->url,
            parent => $asset->parent,
        };
        $data->{ $asset->id } = $hash;
    }
    return {
        label     => 'exported_asset',
        base_path => 'assets',
        assets    => $data,
#        objs      => \@assets,
    };
}

sub finalize {
    my $app = shift;
    my ( $blog, $theme_hash, $tmpdir, $setting ) = @_;
    my $sf_hash = $theme_hash->{elements}{default_assets}
        or return 1;
    my $exts = MT->config->ThemeStaticFileExtensions || _default_allowed_extensions();
    $exts = [ split /[\s,]+/, $exts ] if !ref $exts;
    my $assets = $sf_hash->{data}{assets};

    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new('Local');

    # 一時ディレクトリに'assets'作成
    my $outdir = File::Spec->catdir( $tmpdir, 'assets' );
    $fmgr->mkpath( $outdir )
        or return $app->error(
            $app->translate(
                'Failed to make assets directory [_1]',
                $fmgr->errstr,
        ));

    for my $basename ( keys %$assets ) {
        my $asset = $assets->{$basename};

        # 出力先ディレクトリにファイル名作成
        my $path = File::Spec->catfile( $outdir, $asset->{file_name} );

        # 出力先ディレクトリにファイル出力
        defined $fmgr->put( $asset->{file_path}, $path, 'upload')
            or return $app->error(
                $app->translate(
                    'Failed to publish asset file [_1]',
                    $fmgr->errstr,
            ));
    }
    return 1;
}

sub _default_allowed_extensions {
    return [ qw(
        jpg jpeg gif png js css ico flv swf
    )];
}

sub import {
    my ( $element, $theme, $obj_to_apply ) = @_;
    my $assets = $element->{data}{assets};
    my $base_path = $element->{data}{base_path};
    _add_assets( $theme, $obj_to_apply, $assets, $base_path, 'asset' )
        or die "Failed to create theme default Assets";
    return 1;
}


sub _add_assets {
    my ( $theme, $blog, $assets, $base_path, $class ) = @_;
    my $app = MT->instance;

    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new('Local');

    for my $basename ( keys %$assets ) {
        my $asset = $assets->{$basename};

        next if MT->model($class)->count({
            label => $asset->{label},
            blog_id  => $blog->id,
            class    => '*'
        });
        next if MT->model($class)->count({
            file_name => $asset->{file_name},
            blog_id  => $blog->id,
            class    => '*'
        });
        my $obj = MT->model($class)->new();

        $obj->blog_id( $blog->id );
        $obj->class( $asset->{class} );
        $obj->label( $asset->{label} );
#my $url = $blog->site_url . '/' . $base_path . '/' . $asset->{file_name};
#my $site_url = $blog->site_url;
#$url =~ s/$site_url/%r/;
        $obj->url( '%r/' . $base_path . '/' . $asset->{file_name} );
        $obj->description( $asset->{description} );

#my $path = $blog->site_path . '/' . $base_path .'/' . $asset->{file_name};
#my $site_path = $blog->site_path;
#$path =~ s/$site_path/%r/;
        $obj->file_path( '%r/' . $base_path .'/' . $asset->{file_name} );
        $obj->file_name( $asset->{file_name} );
        $obj->file_ext( $asset->{file_ext} );
        $obj->mime_type( $asset->{mime_type} );
        $obj->save or die $obj->errstr;

        # 出力先のディレクトリ(assets)作成
        my $outdir = File::Spec->catdir( $blog->site_path, 'assets' );
        $fmgr->mkpath( $outdir )
            or return $app->error(
                $app->translate(
                    'Failed to make assets directory [_1]',
                    $fmgr->errstr,
            ));

        # 出力先ディレクトリにファイル名作成
        my $path = File::Spec->catfile( $outdir, $asset->{file_name} );

        # 出力先ディレクトリにファイル出力
        defined $fmgr->put( $theme->path. '/' . $base_path . '/' .$asset->{file_name}, $path, 'upload')
            or return $app->error(
                $app->translate(
                    'Failed to publish asset file [_1]',
                    $fmgr->errstr,
            ));
    }
    1;
}

sub info {
    my ( $element, $theme, $blog ) = @_;
    my $data = $element->{data}{assets};

    my $plugin = MT->component('AssetExporter');
    return sub {
        $plugin->translate( '[_1] assets', scalar keys %{$element->{data}{assets}} );
    };
}

1;
